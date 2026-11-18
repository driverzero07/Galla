import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/sales_dao.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../../core/utils/day_start.dart';
import '../../auth/data/shop_repository.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';
import '../domain/bill_math.dart';

class BillLineInput {
  const BillLineInput({
    required this.itemId,
    required this.qty,
    required this.unitPrice,
  });
  final String itemId;

  /// Thousandths.
  final int qty;

  /// Price charged on this bill (paisa), possibly overridden.
  final int unitPrice;
}

class BillInput {
  const BillInput({
    required this.lines,
    this.discount = 0,
    this.customerId,
    this.credit = false,
    this.paidNow = 0,
  });
  final List<BillLineInput> lines;
  final int discount;

  /// null = Naqad customer.
  final String? customerId;
  final bool credit;
  final int paidNow;
}

class SavedBill {
  const SavedBill(this.saleId, this.billNo);
  final String saleId;
  final String billNo;
}

enum BillError {
  empty,
  badQuantity,
  badPrice,
  duplicateItem,
  discountTooHigh,
  unknownItem,
  unknownCustomer,

  /// Naqad customer can never carry udhaar (Part 0 rule 5).
  creditNeedsCustomer,

  /// A line asks for more than the stock on hand. Nothing is sold that is
  /// not in the inventory.
  insufficientStock,
}

class BillException implements Exception {
  const BillException(this.error);
  final BillError error;
  @override
  String toString() => 'BillException($error)';
}

enum SaleActionError { notFound, alreadyCancelled, nothingToReturn, overReturn }

class SaleActionException implements Exception {
  const SaleActionException(this.error);
  final SaleActionError error;
  @override
  String toString() => 'SaleActionException($error)';
}

/// An item whose quantity on the bill is more than the stock on hand. Such a
/// bill cannot be saved.
class StockShortage {
  const StockShortage(this.itemId, this.name, this.needed, this.available);
  final String itemId;
  final String name;
  final int needed;
  final int available;
}

class ReturnResult {
  const ReturnResult(this.returnId, this.amount, this.ledgerCredit, this.cashRefund);
  final String returnId;
  final int amount;
  final int ledgerCredit;
  final int cashRefund;
}

class SalesRepository {
  SalesRepository(this._db, this._shopId, this._now, {Random? random})
      : _random = random ?? Random.secure();

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  final Random _random;
  static const _uuid = Uuid();

  static const billPrefixKey = 'bill_prefix';
  static const billSeqKey = 'bill_seq';

  /// Stock on hand for one item (thousandths); 0 when nothing was ever added.
  Future<int> stockOf(String itemId) async =>
      (await _db.salesDao.stocksOf([itemId]))[itemId] ?? 0;

  /// Items whose quantity on this bill is more than the stock on hand.
  Future<List<StockShortage>> shortages(List<BillLineInput> lines) async {
    final stocks = await _db.salesDao.stocksOf(lines.map((l) => l.itemId));
    final result = <StockShortage>[];
    for (final l in lines) {
      final available = stocks[l.itemId] ?? 0;
      if (l.qty > available) {
        final item = await _db.inventoryDao.itemById(l.itemId);
        result.add(StockShortage(
            l.itemId, item?.name ?? '', l.qty, available));
      }
    }
    return result;
  }

  /// Part 0 rule 1: sale + lines + negative stock movements + (for unpaid
  /// money) a customer ledger row, all in ONE transaction, all queued for
  /// sync. Any failure writes nothing, not even a bill number.
  Future<SavedBill> saveBill(BillInput input) async {
    _validate(input);
    final shopId = _shopId();
    final now = _now();
    final saleId = _uuid.v4();
    final naqadId = naqadCustomerId(shopId);
    final customerId = input.customerId ?? naqadId;
    final isNaqad = customerId == naqadId;
    if (input.credit && isNaqad) {
      throw const BillException(BillError.creditNeedsCustomer);
    }

    late String billNo;
    await writeWithOutbox(_db, (outbox) async {
      if (!isNaqad && await _db.khataDao.customerById(customerId) == null) {
        throw const BillException(BillError.unknownCustomer);
      }

      // Look items up (cost snapshot, name snapshot) inside the transaction.
      final items = <String, Item>{};
      for (final l in input.lines) {
        final item = await _db.inventoryDao.itemById(l.itemId);
        if (item == null) throw const BillException(BillError.unknownItem);
        items[l.itemId] = item;
      }

      // Nothing is sold that is not in the inventory: every line must be
      // covered by the stock on hand, checked inside the same transaction.
      final stocks =
          await _db.salesDao.stocksOf(input.lines.map((l) => l.itemId));
      for (final l in input.lines) {
        if (l.qty > (stocks[l.itemId] ?? 0)) {
          throw const BillException(BillError.insufficientStock);
        }
      }

      final totals = computeTotals(
        [for (final l in input.lines) (qty: l.qty, unitPrice: l.unitPrice)],
        input.discount,
      );
      if (input.discount > totals.subtotal) {
        throw const BillException(BillError.discountTooHigh);
      }
      final pay = resolvePayment(
        total: totals.total,
        credit: input.credit,
        paidNow: input.paidNow,
      );

      billNo = await _nextBillNo();
      final sale = await _db.into(_db.sales).insertReturning(
            SalesCompanion.insert(
              id: saleId,
              shopId: shopId,
              billNo: billNo,
              customerId: customerId,
              subtotal: totals.subtotal,
              discount: Value(totals.discount),
              total: totals.total,
              paidAmount: Value(pay.paid),
              paymentMode: pay.mode,
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'sales',
          rowId: saleId,
          payload: sale.toJson(),
          op: OutboxOp.insert);

      for (final l in input.lines) {
        final item = items[l.itemId]!;
        final line = await _db.into(_db.saleLines).insertReturning(
              SaleLinesCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                saleId: saleId,
                itemId: l.itemId,
                nameSnapshot: item.name,
                qty: l.qty,
                unitPrice: l.unitPrice,
                costSnapshot: item.costPrice,
                lineTotal: lineTotal(l.qty, l.unitPrice),
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'sale_lines',
            rowId: line.id,
            payload: line.toJson(),
            op: OutboxOp.insert);

        await _movement(outbox,
            shopId: shopId,
            itemId: l.itemId,
            qty: -l.qty,
            reason: StockReason.sale,
            refType: 'sale',
            refId: saleId,
            now: now);
      }

      if (pay.unpaid > 0) {
        await _ledger(outbox,
            shopId: shopId,
            customerId: customerId,
            type: CustomerLedgerType.saleCredit,
            amount: pay.unpaid,
            refId: saleId,
            now: now);
      }
    }, now: () => now);
    return SavedBill(saleId, billNo);
  }

  /// Return goods from a bill. Stock comes back through `return_in`
  /// movements. Money still owed on the bill is taken off the customer's
  /// khata; the rest is a cash refund note.
  Future<ReturnResult> createReturn(
    String saleId,
    Map<String, int> qtyByItem, {
    String? note,
  }) async {
    final shopId = _shopId();
    final now = _now();
    final returnId = _uuid.v4();
    late ReturnResult result;

    await writeWithOutbox(_db, (outbox) async {
      final sale = await _db.salesDao.saleById(saleId);
      if (sale == null) {
        throw const SaleActionException(SaleActionError.notFound);
      }
      if (sale.status != DocStatus.active) {
        throw const SaleActionException(SaleActionError.alreadyCancelled);
      }
      final lines = await _db.salesDao.linesOf(saleId);
      final returned = await _db.salesDao.returnedQtyByItem(saleId);

      final picked = <({SaleLine line, int qty})>[];
      for (final e in qtyByItem.entries) {
        if (e.value <= 0) continue;
        final line = lines.where((l) => l.itemId == e.key).firstOrNull;
        if (line == null) {
          throw const SaleActionException(SaleActionError.nothingToReturn);
        }
        final remaining = line.qty - (returned[e.key] ?? 0);
        if (e.value > remaining) {
          throw const SaleActionException(SaleActionError.overReturn);
        }
        picked.add((line: line, qty: e.value));
      }
      if (picked.isEmpty) {
        throw const SaleActionException(SaleActionError.nothingToReturn);
      }

      final prior = await _db.salesDao.returnsOf(saleId);
      final plan = planReturn(
        lines: [
          for (final p in picked) (qty: p.qty, unitPrice: p.line.unitPrice),
        ],
        billSubtotal: sale.subtotal,
        billDiscount: sale.discount,
        billTotal: sale.total,
        billPaid: sale.paidAmount,
        priorValue: prior.fold<int>(0, (s, r) => s + r.amount),
        priorLedgerCredits: prior.fold<int>(0, (s, r) => s + r.ledgerCredit),
      );
      final amounts = plan.lineAmounts;
      final total = plan.total;
      final split = plan.split;

      final header = await _db.into(_db.saleReturns).insertReturning(
            SaleReturnsCompanion.insert(
              id: returnId,
              shopId: shopId,
              saleId: saleId,
              amount: total,
              ledgerCredit: Value(split.ledgerCredit),
              cashRefund: Value(split.cashRefund),
              note: Value(note),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'sale_returns',
          rowId: returnId,
          payload: header.toJson(),
          op: OutboxOp.insert);

      for (var i = 0; i < picked.length; i++) {
        final p = picked[i];
        final row = await _db.into(_db.saleReturnLines).insertReturning(
              SaleReturnLinesCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                returnId: returnId,
                saleId: saleId,
                itemId: p.line.itemId,
                qty: p.qty,
                amount: amounts[i],
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'sale_return_lines',
            rowId: row.id,
            payload: row.toJson(),
            op: OutboxOp.insert);
        await _movement(outbox,
            shopId: shopId,
            itemId: p.line.itemId,
            qty: p.qty,
            reason: StockReason.returnIn,
            refType: 'sale_return',
            refId: returnId,
            now: now);
      }

      if (split.ledgerCredit > 0) {
        await _ledger(outbox,
            shopId: shopId,
            customerId: sale.customerId,
            type: CustomerLedgerType.returnCredit,
            amount: -split.ledgerCredit,
            refId: saleId,
            now: now);
      }
      result = ReturnResult(
          returnId, total, split.ledgerCredit, split.cashRefund);
    }, now: () => now);
    return result;
  }

  /// Whole-bill reversal (Part 0 rule 3). The bill is marked cancelled and
  /// reversing entries put back exactly the stock still out and the khata
  /// effect still standing, taking earlier returns into account.
  Future<void> cancelSale(String saleId) async {
    final shopId = _shopId();
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      final sale = await _db.salesDao.saleById(saleId);
      if (sale == null) {
        throw const SaleActionException(SaleActionError.notFound);
      }
      if (sale.status == DocStatus.cancelled) {
        throw const SaleActionException(SaleActionError.alreadyCancelled);
      }
      final lines = await _db.salesDao.linesOf(saleId);
      final returned = await _db.salesDao.returnedQtyByItem(saleId);

      for (final l in lines) {
        final remaining = l.qty - (returned[l.itemId] ?? 0);
        if (remaining > 0) {
          await _movement(outbox,
              shopId: shopId,
              itemId: l.itemId,
              qty: remaining,
              reason: StockReason.cancelSale,
              refType: 'sale',
              refId: saleId,
              now: now);
        }
      }

      final ledger = _db.customerLedger;
      final sum = ledger.amount.sum();
      final row = await (_db.selectOnly(ledger)
            ..addColumns([sum])
            ..where(ledger.refId.equals(saleId) &
                ledger.customerId.equals(sale.customerId)))
          .getSingle();
      final net = row.read(sum) ?? 0;
      if (net != 0) {
        await _ledger(outbox,
            shopId: shopId,
            customerId: sale.customerId,
            type: CustomerLedgerType.adjustment,
            amount: -net,
            refId: saleId,
            note: 'cancel',
            now: now);
      }

      await (_db.update(_db.sales)..where((t) => t.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value(DocStatus.cancelled),
          updatedAt: Value(now),
        ),
      );
      final updated = await _db.salesDao.saleById(saleId);
      if (updated != null) {
        outbox.record(table: 'sales', rowId: saleId, payload: updated.toJson());
      }
    }, now: () => now);
  }

  // ---------------------------------------------------------------- helpers

  void _validate(BillInput input) {
    if (input.lines.isEmpty) throw const BillException(BillError.empty);
    final seen = <String>{};
    for (final l in input.lines) {
      if (l.qty <= 0) throw const BillException(BillError.badQuantity);
      if (l.unitPrice < 0) throw const BillException(BillError.badPrice);
      if (!seen.add(l.itemId)) {
        throw const BillException(BillError.duplicateItem);
      }
    }
    if (input.discount < 0) {
      throw const BillException(BillError.discountTooHigh);
    }
  }

  /// Per-device prefix plus a sequence, so offline devices never clash
  /// (rule 11). Stored in local-only device state; runs inside the sale
  /// transaction so a failed save does not burn a number.
  Future<String> _nextBillNo() =>
      _db.deviceStateDao.nextNumber(billSeqKey, _random);

  Future<void> _movement(
    OutboxBatch outbox, {
    required String shopId,
    required String itemId,
    required int qty,
    required String reason,
    required String refType,
    required String refId,
    required DateTime now,
  }) async {
    final m = await _db.into(_db.stockMovements).insertReturning(
          StockMovementsCompanion.insert(
            id: _uuid.v4(),
            shopId: shopId,
            itemId: itemId,
            qty: qty,
            reason: reason,
            refType: Value(refType),
            refId: Value(refId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    outbox.record(
        table: 'stock_movements',
        rowId: m.id,
        payload: m.toJson(),
        op: OutboxOp.insert);
  }

  Future<void> _ledger(
    OutboxBatch outbox, {
    required String shopId,
    required String customerId,
    required String type,
    required int amount,
    required String refId,
    required DateTime now,
    String? note,
  }) async {
    final l = await _db.into(_db.customerLedger).insertReturning(
          CustomerLedgerCompanion.insert(
            id: _uuid.v4(),
            shopId: shopId,
            customerId: customerId,
            type: type,
            amount: amount,
            refId: Value(refId),
            note: Value(note),
            date: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    outbox.record(
        table: 'customer_ledger',
        rowId: l.id,
        payload: l.toJson(),
        op: OutboxOp.insert);
  }
}

/// Stores the unsaved bill on this device only (never synced).
class BillDraftStore {
  BillDraftStore(this._db, this._shopId);

  final AppDatabase _db;
  final String Function() _shopId;

  String get _key => 'bill_draft:${_shopId()}';

  Future<String?> load() => _db.deviceStateDao.get(_key);
  Future<void> save(String json) => _db.deviceStateDao.set(_key, json);
  Future<void> clear() => _db.deviceStateDao.remove(_key);
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

final billDraftStoreProvider = Provider<BillDraftStore>((ref) {
  return BillDraftStore(
      ref.watch(appDatabaseProvider), () => ref.read(shopIdProvider));
});

/// Start of today in local time and of tomorrow.
({DateTime from, DateTime to}) todayRange(DateTime now) {
  final from = DateTime(now.year, now.month, now.day);
  return (from: from, to: from.add(const Duration(days: 1)));
}

final todaySalesProvider =
    StreamProvider.autoDispose<List<SaleListRow>>((ref) {
  final shopId = ref.watch(shopIdProvider);
  // Re-runs at midnight, so "today" rolls over without reopening the app.
  final from = ref.watch(dayStartProvider).valueOrNull;
  if (from == null) return const Stream<List<SaleListRow>>.empty();
  final range = todayRange(from);
  return ref
      .watch(appDatabaseProvider)
      .salesDao
      .watchSalesBetween(shopId, range.from, range.to);
});

final saleDetailProvider = FutureProvider.autoDispose
    .family<SaleDetailData?, String>((ref, saleId) {
  return ref.watch(appDatabaseProvider).salesDao.saleDetail(saleId);
});

final quickPickProvider = FutureProvider.autoDispose<List<Item>>((ref) {
  final shopId = ref.watch(shopIdProvider);
  final since = ref.watch(clockProvider)().subtract(const Duration(days: 30));
  return ref
      .watch(appDatabaseProvider)
      .salesDao
      .quickPickItems(shopId, since, limit: 8);
});
