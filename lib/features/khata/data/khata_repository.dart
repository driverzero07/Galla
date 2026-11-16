import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/khata_dao.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../auth/data/shop_repository.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';
import '../domain/ledger_history.dart';

enum LedgerEntryError { badAmount, unknownParty, systemCustomer }

class LedgerEntryException implements Exception {
  const LedgerEntryException(this.error);
  final LedgerEntryError error;
  @override
  String toString() => 'LedgerEntryException($error)';
}

/// Money in and out of khata: payments received, manual udhaar and payments
/// to suppliers. Every write is one append-only ledger row (plus its outbox
/// row, in the same transaction). Balances are never stored.
class KhataRepository {
  KhataRepository(this._db, this._shopId, this._now);

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  /// The picked day with the current time of day, so entries made on the same
  /// day keep the order they were written in.
  DateTime _stamp(DateTime? date, DateTime now) {
    if (date == null) return now;
    return DateTime(date.year, date.month, date.day, now.hour, now.minute,
        now.second);
  }

  Future<void> _requireCustomer(String id) async {
    if (id == naqadCustomerId(_shopId())) {
      throw const LedgerEntryException(LedgerEntryError.systemCustomer);
    }
    if (await _db.khataDao.customerById(id) == null) {
      throw const LedgerEntryException(LedgerEntryError.unknownParty);
    }
  }

  Future<String> _customerRow(
    String customerId,
    String type,
    int signedAmount, {
    String? note,
    DateTime? date,
  }) async {
    final shopId = _shopId();
    final now = _now();
    final id = _uuid.v4();
    await writeWithOutbox(_db, (outbox) async {
      final row = await _db.into(_db.customerLedger).insertReturning(
            CustomerLedgerCompanion.insert(
              id: id,
              shopId: shopId,
              customerId: customerId,
              type: type,
              amount: signedAmount,
              note: Value(_cleanNote(note)),
              date: _stamp(date, now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'customer_ledger',
          rowId: id,
          payload: row.toJson(),
          op: OutboxOp.insert);
    }, now: () => now);
    return id;
  }

  /// Paisay mile. [amount] is positive paisa; it may be more than the
  /// baqaya (the customer then has an advance).
  Future<String> receivePayment(String customerId, int amount,
      {String? note, DateTime? date}) async {
    if (amount <= 0) throw const LedgerEntryException(LedgerEntryError.badAmount);
    await _requireCustomer(customerId);
    return _customerRow(customerId, CustomerLedgerType.paymentReceived, -amount,
        note: note, date: date);
  }

  /// Udhaar likho: manual udhaar without items.
  Future<String> addUdhaar(String customerId, int amount,
      {String? note, DateTime? date}) async {
    if (amount <= 0) throw const LedgerEntryException(LedgerEntryError.badAmount);
    await _requireCustomer(customerId);
    return _customerRow(customerId, CustomerLedgerType.manualUdhaar, amount,
        note: note, date: date);
  }

  /// Paisay diye: payment to a supplier; may overpay (advance).
  Future<String> paySupplier(String supplierId, int amount,
      {String? note, DateTime? date}) async {
    if (amount <= 0) throw const LedgerEntryException(LedgerEntryError.badAmount);
    if (await _db.khataDao.supplierById(supplierId) == null) {
      throw const LedgerEntryException(LedgerEntryError.unknownParty);
    }
    final shopId = _shopId();
    final now = _now();
    final id = _uuid.v4();
    await writeWithOutbox(_db, (outbox) async {
      final row = await _db.into(_db.supplierLedger).insertReturning(
            SupplierLedgerCompanion.insert(
              id: id,
              shopId: shopId,
              supplierId: supplierId,
              type: SupplierLedgerType.paymentMade,
              amount: -amount,
              note: Value(_cleanNote(note)),
              date: _stamp(date, now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'supplier_ledger',
          rowId: id,
          payload: row.toJson(),
          op: OutboxOp.insert);
    }, now: () => now);
    return id;
  }

  String? _cleanNote(String? n) {
    final t = n?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  // ------------------------------------------------------------ history

  Future<History> customerHistory(String customerId) async {
    final rows = await _db.khataDao.customerLedgerRows(customerId);
    return _customerHistory(rows);
  }

  Stream<History> watchCustomerHistory(String customerId) =>
      _db.khataDao.watchCustomerLedger(customerId).asyncMap(_customerHistory);

  Future<History> _customerHistory(List<RawLedger> rows) async {
    final bills = <String, ({String billNo, List<String> names})>{};
    for (final id in {
      for (final r in rows)
        if (r.refId != null && _isBillRef(r.type)) r.refId!
    }) {
      final sale = await _db.salesDao.saleById(id);
      if (sale == null) continue;
      final lines = await _db.salesDao.linesOf(id);
      bills[id] = (
        billNo: sale.billNo,
        names: [for (final l in lines) l.nameSnapshot],
      );
    }
    return buildHistory(rows, describe: (r) {
      final b = r.refId == null ? null : bills[r.refId!];
      if (b == null) return (docNo: null, itemsText: null, paidNote: null);
      return (
        docNo: b.billNo,
        itemsText: r.type == CustomerLedgerType.saleCredit
            ? joinItemNames(b.names)
            : null,
        paidNote: null,
      );
    });
  }

  bool _isBillRef(String type) =>
      type == CustomerLedgerType.saleCredit ||
      type == CustomerLedgerType.returnCredit ||
      type == CustomerLedgerType.adjustment;

  Stream<History> watchSupplierHistory(String supplierId) =>
      _db.khataDao.watchSupplierLedger(supplierId).asyncMap(_supplierHistory);

  Future<History> _supplierHistory(List<RawLedger> rows) async {
    final briefs = await _db.purchasesDao.briefs([
      for (final r in rows)
        if (r.type == SupplierLedgerType.purchaseCredit && r.refId != null)
          r.refId!
    ]);
    return buildHistory(rows, describe: (r) {
      final b = r.refId == null ? null : briefs[r.refId!];
      if (b == null) return (docNo: null, itemsText: null, paidNote: null);
      return (
        docNo: b.purchase.purchaseNo.isEmpty ? null : b.purchase.purchaseNo,
        itemsText: joinItemNames(b.itemNames),
        paidNote: b.purchase.paidAmount,
      );
    });
  }

  Future<History> supplierHistory(String supplierId) async {
    final rows = await (_db.select(_db.supplierLedger)
          ..where((t) => t.supplierId.equals(supplierId)))
        .get();
    return _supplierHistory([
      for (final r in rows)
        (
          id: r.id,
          type: r.type,
          amount: r.amount,
          date: r.date,
          createdAt: r.createdAt,
          refId: r.refId,
          note: r.note,
        ),
    ]);
  }
}

final khataRepositoryProvider = Provider<KhataRepository>((ref) {
  return KhataRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

final customerHistoryProvider =
    StreamProvider.autoDispose.family<History, String>((ref, id) {
  return ref.watch(khataRepositoryProvider).watchCustomerHistory(id);
});

final supplierHistoryProvider =
    StreamProvider.autoDispose.family<History, String>((ref, id) {
  return ref.watch(khataRepositoryProvider).watchSupplierHistory(id);
});

final customerProvider =
    StreamProvider.autoDispose.family<Customer?, String>((ref, id) {
  return ref.watch(appDatabaseProvider).khataDao.watchCustomer(id);
});

final supplierProvider =
    StreamProvider.autoDispose.family<Supplier?, String>((ref, id) {
  return ref.watch(appDatabaseProvider).khataDao.watchSupplier(id);
});
