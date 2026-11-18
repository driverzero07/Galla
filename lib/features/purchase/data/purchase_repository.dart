import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/purchases_dao.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';
import '../../bill/domain/bill_math.dart';

class PurchaseLineInput {
  const PurchaseLineInput({
    required this.itemId,
    required this.qty,
    required this.unitCost,
  });
  final String itemId;

  /// Thousandths of the item's unit.
  final int qty;

  /// Paisa per unit.
  final int unitCost;

  int get total => lineTotal(qty, unitCost);
}

class PurchaseInput {
  const PurchaseInput({
    required this.supplierId,
    required this.lines,
    this.paidNow = 0,
    this.invoiceImagePath,
  });
  final String supplierId;
  final List<PurchaseLineInput> lines;
  final int paidNow;
  final String? invoiceImagePath;

  int get total => lines.fold<int>(0, (s, l) => s + l.total);
}

enum PurchaseError {
  empty,
  badQuantity,
  badCost,
  duplicateItem,
  unknownSupplier,
  unknownItem,
  badPaid,

  /// Paying the supplier more than the cash in hand.
  insufficientCash,
}

class PurchaseException implements Exception {
  const PurchaseException(this.error, {this.available = 0});
  final PurchaseError error;

  /// Cash in hand (paisa) when [error] is insufficientCash.
  final int available;
  @override
  String toString() => 'PurchaseException($error)';
}

class SavedPurchase {
  const SavedPurchase(this.purchaseId, this.purchaseNo, this.total, this.unpaid);
  final String purchaseId;
  final String purchaseNo;
  final int total;
  final int unpaid;
}

/// Stock coming in. One transaction: purchase + lines, positive stock
/// movements, new `items.cost_price`, and a supplier_ledger row for the
/// unpaid amount only. Nothing is ever deleted.
class PurchaseRepository {
  PurchaseRepository(this._db, this._shopId, this._now, {Random? random})
      : _random = random ?? Random.secure();

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  final Random _random;
  static const _uuid = Uuid();
  static const purchaseSeqKey = 'purchase_seq';

  Future<SavedPurchase> savePurchase(PurchaseInput input) async {
    _validate(input);
    final shopId = _shopId();
    final now = _now();
    final purchaseId = _uuid.v4();
    final total = input.total;
    // Paying the whole total (or more) is simply a fully paid purchase.
    final paid = input.paidNow > total ? total : input.paidNow;
    final unpaid = total - paid;

    return writeWithOutbox(_db, (outbox) async {
      if (await _db.khataDao.supplierById(input.supplierId) == null) {
        throw const PurchaseException(PurchaseError.unknownSupplier);
      }
      if (paid > 0) {
        final cash = await AccountsRepository.cashInHandOf(_db, shopId);
        if (paid > cash) {
          throw PurchaseException(PurchaseError.insufficientCash,
              available: cash < 0 ? 0 : cash);
        }
      }
      final no = await _db.deviceStateDao.nextNumber(purchaseSeqKey, _random);
      final p = await _db.into(_db.purchases).insertReturning(
            PurchasesCompanion.insert(
              id: purchaseId,
              shopId: shopId,
              supplierId: input.supplierId,
              purchaseNo: Value(no),
              total: total,
              paidAmount: Value(paid),
              invoiceImagePath: Value(input.invoiceImagePath),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'purchases',
          rowId: purchaseId,
          payload: p.toJson(),
          op: OutboxOp.insert);

      for (final l in input.lines) {
        final item = await _db.inventoryDao.itemById(l.itemId);
        if (item == null) {
          throw const PurchaseException(PurchaseError.unknownItem);
        }
        final pl = await _db.into(_db.purchaseLines).insertReturning(
              PurchaseLinesCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                purchaseId: purchaseId,
                itemId: l.itemId,
                qty: l.qty,
                unitCost: l.unitCost,
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'purchase_lines',
            rowId: pl.id,
            payload: pl.toJson(),
            op: OutboxOp.insert);

        final m = await _db.into(_db.stockMovements).insertReturning(
              StockMovementsCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                itemId: l.itemId,
                qty: l.qty,
                reason: StockReason.purchase,
                refType: const Value('purchase'),
                refId: Value(purchaseId),
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'stock_movements',
            rowId: m.id,
            payload: m.toJson(),
            op: OutboxOp.insert);

        // Latest cost wins.
        if (item.costPrice != l.unitCost) {
          await (_db.update(_db.items)..where((t) => t.id.equals(l.itemId)))
              .write(ItemsCompanion(
            costPrice: Value(l.unitCost),
            updatedAt: Value(now),
          ));
          final updated = await _db.inventoryDao.itemById(l.itemId);
          if (updated != null) {
            outbox.record(
                table: 'items', rowId: l.itemId, payload: updated.toJson());
          }
        }
      }

      if (unpaid > 0) {
        final row = await _db.into(_db.supplierLedger).insertReturning(
              SupplierLedgerCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                supplierId: input.supplierId,
                type: SupplierLedgerType.purchaseCredit,
                amount: unpaid,
                refId: Value(purchaseId),
                date: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'supplier_ledger',
            rowId: row.id,
            payload: row.toJson(),
            op: OutboxOp.insert);
      }
      return SavedPurchase(purchaseId, no, total, unpaid);
    }, now: () => now);
  }

  void _validate(PurchaseInput input) {
    if (input.lines.isEmpty) throw const PurchaseException(PurchaseError.empty);
    if (input.paidNow < 0) throw const PurchaseException(PurchaseError.badPaid);
    final seen = <String>{};
    for (final l in input.lines) {
      if (l.qty <= 0) throw const PurchaseException(PurchaseError.badQuantity);
      if (l.unitCost < 0) throw const PurchaseException(PurchaseError.badCost);
      if (!seen.add(l.itemId)) {
        throw const PurchaseException(PurchaseError.duplicateItem);
      }
    }
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return PurchaseRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

final purchaseListProvider =
    StreamProvider.autoDispose<List<PurchaseListRow>>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(appDatabaseProvider).purchasesDao.watchPurchases(shopId);
});

final purchaseDetailProvider = FutureProvider.autoDispose
    .family<PurchaseDetailData?, String>((ref, id) {
  return ref.watch(appDatabaseProvider).purchasesDao.detail(id);
});
