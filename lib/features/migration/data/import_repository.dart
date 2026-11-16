import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';
import '../domain/import_rows.dart';

class ImportPartyInput {
  const ImportPartyInput({required this.name, this.phone, this.paisa = 0});
  final String name;

  /// Normalised E.164 or null.
  final String? phone;

  /// Signed opening balance (+ owed to us for customers, + we owe for
  /// suppliers).
  final int paisa;
}

class ImportItemInput {
  const ImportItemInput({
    required this.name,
    this.unit = ItemUnit.kg,
    this.cost = 0,
    this.price = 0,
    this.stock = 0,
    this.low = 0,
    this.barcode,
  });
  final String name;
  final String unit;
  final int cost;
  final int price;
  final int stock;
  final int low;
  final String? barcode;
}

class ImportResult {
  const ImportResult(this.batchId, this.count, this.totalAmount);
  final String batchId;
  final int count;
  final int totalAmount;
}

enum ImportError { empty, badRow, barcodeTaken, notFound, alreadyUndone, undoBlocked }

class ImportException implements Exception {
  const ImportException(this.error, {this.count = 0});
  final ImportError error;

  /// For [ImportError.undoBlocked]: how many rows have later activity.
  final int count;
  @override
  String toString() => 'ImportException($error, $count)';
}

/// Writes a whole migration in ONE transaction (all rows or none) and can
/// undo a whole batch while nothing else has touched it. Nothing is deleted:
/// undo adds reversing entries and archives what the batch created.
class ImportRepository {
  ImportRepository(this._db, this._shopId, this._now);

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  Future<ImportResult> commitParties({
    required String kind,
    required List<ImportPartyInput> rows,
    String method = ImportMethod.file,
    String? photoPath,
  }) async {
    assert(kind == ImportKind.customers || kind == ImportKind.suppliers);
    if (rows.isEmpty) throw const ImportException(ImportError.empty);
    for (final r in rows) {
      if (r.name.trim().isEmpty || r.paisa.abs() > maxOpeningBalance) {
        throw const ImportException(ImportError.badRow);
      }
    }
    final shopId = _shopId();
    final now = _now();
    final batchId = _uuid.v4();
    final isCustomer = kind == ImportKind.customers;
    var total = 0;

    await writeWithOutbox(_db, (outbox) async {
      final ids = <String>[];
      for (final r in rows) {
        final id = _uuid.v4();
        ids.add(id);
        if (isCustomer) {
          final c = await _db.into(_db.customers).insertReturning(
                CustomersCompanion.insert(
                  id: id,
                  shopId: shopId,
                  name: r.name.trim(),
                  phone: Value(r.phone),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          outbox.record(
              table: 'customers',
              rowId: id,
              payload: c.toJson(),
              op: OutboxOp.insert);
        } else {
          final s = await _db.into(_db.suppliers).insertReturning(
                SuppliersCompanion.insert(
                  id: id,
                  shopId: shopId,
                  name: r.name.trim(),
                  phone: Value(r.phone),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          outbox.record(
              table: 'suppliers',
              rowId: id,
              payload: s.toJson(),
              op: OutboxOp.insert);
        }
        if (r.paisa != 0) {
          total += r.paisa;
          if (isCustomer) {
            final l = await _db.into(_db.customerLedger).insertReturning(
                  CustomerLedgerCompanion.insert(
                    id: _uuid.v4(),
                    shopId: shopId,
                    customerId: id,
                    type: CustomerLedgerType.opening,
                    amount: r.paisa,
                    refId: Value(batchId),
                    note: const Value('import'),
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
          } else {
            final l = await _db.into(_db.supplierLedger).insertReturning(
                  SupplierLedgerCompanion.insert(
                    id: _uuid.v4(),
                    shopId: shopId,
                    supplierId: id,
                    type: SupplierLedgerType.opening,
                    amount: r.paisa,
                    refId: Value(batchId),
                    note: const Value('import'),
                    date: now,
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            outbox.record(
                table: 'supplier_ledger',
                rowId: l.id,
                payload: l.toJson(),
                op: OutboxOp.insert);
          }
        }
      }
      await _insertBatch(outbox,
          id: batchId,
          kind: kind,
          method: method,
          count: rows.length,
          total: total,
          ids: ids,
          photoPath: photoPath,
          now: now);
    }, now: () => now);
    return ImportResult(batchId, rows.length, total);
  }

  Future<ImportResult> commitItems({
    required List<ImportItemInput> rows,
    String method = ImportMethod.file,
  }) async {
    if (rows.isEmpty) throw const ImportException(ImportError.empty);
    for (final r in rows) {
      if (r.name.trim().isEmpty || r.cost < 0 || r.price < 0 || r.low < 0) {
        throw const ImportException(ImportError.badRow);
      }
    }
    final shopId = _shopId();
    final now = _now();
    final batchId = _uuid.v4();

    await writeWithOutbox(_db, (outbox) async {
      final ids = <String>[];
      for (final r in rows) {
        final barcode = (r.barcode?.trim().isEmpty ?? true) ? null : r.barcode!.trim();
        if (barcode != null) {
          final clash = await (_db.select(_db.items)
                ..where((t) =>
                    t.shopId.equals(shopId) & t.barcode.equals(barcode)))
              .get();
          if (clash.isNotEmpty) {
            throw const ImportException(ImportError.barcodeTaken);
          }
        }
        final id = _uuid.v4();
        ids.add(id);
        final item = await _db.into(_db.items).insertReturning(
              ItemsCompanion.insert(
                id: id,
                shopId: shopId,
                name: r.name.trim(),
                barcode: Value(barcode),
                unit: Value(r.unit),
                costPrice: Value(r.cost),
                salePrice: Value(r.price),
                lowStockLevel: Value(r.low),
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'items',
            rowId: id,
            payload: item.toJson(),
            op: OutboxOp.insert);
        if (r.stock != 0) {
          final m = await _db.into(_db.stockMovements).insertReturning(
                StockMovementsCompanion.insert(
                  id: _uuid.v4(),
                  shopId: shopId,
                  itemId: id,
                  qty: r.stock,
                  reason: StockReason.opening,
                  refType: const Value('import'),
                  refId: Value(batchId),
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
      }
      await _insertBatch(outbox,
          id: batchId,
          kind: ImportKind.items,
          method: method,
          count: rows.length,
          total: 0,
          ids: ids,
          photoPath: null,
          now: now);
    }, now: () => now);
    return ImportResult(batchId, rows.length, 0);
  }

  Future<void> _insertBatch(
    OutboxBatch outbox, {
    required String id,
    required String kind,
    required String method,
    required int count,
    required int total,
    required List<String> ids,
    required String? photoPath,
    required DateTime now,
  }) async {
    final b = await _db.into(_db.importBatches).insertReturning(
          ImportBatchesCompanion.insert(
            id: id,
            shopId: _shopId(),
            kind: kind,
            method: method,
            rowCount: count,
            totalAmount: Value(total),
            entityIds: jsonEncode(ids),
            photoPath: Value(photoPath),
            createdAt: now,
            updatedAt: now,
          ),
        );
    outbox.record(
        table: 'import_batches',
        rowId: id,
        payload: b.toJson(),
        op: OutboxOp.insert);
  }

  // ------------------------------------------------------------- undo

  /// How many rows of the batch have been touched since the import (so undo
  /// would have to leave them alone). 0 means the batch can be undone.
  Future<int> blockedCount(String batchId) async {
    final batch = await _batch(batchId);
    if (batch == null) return 0;
    var blocked = 0;
    for (final id in _ids(batch)) {
      if (await _touched(batch, id)) blocked++;
    }
    return blocked;
  }

  Future<ImportBatch?> _batch(String id) => (_db.select(_db.importBatches)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  List<String> _ids(ImportBatch b) =>
      [for (final e in jsonDecode(b.entityIds) as List) e as String];

  Future<bool> _touched(ImportBatch b, String id) async {
    switch (b.kind) {
      case ImportKind.customers:
        final other = await (_db.select(_db.customerLedger)
              ..where((t) =>
                  t.customerId.equals(id) &
                  (t.type.equals(CustomerLedgerType.opening).not() |
                      t.refId.equals(b.id).not())))
            .get();
        if (other.isNotEmpty) return true;
        final sales = await (_db.select(_db.sales)
              ..where((t) => t.customerId.equals(id)))
            .get();
        return sales.isNotEmpty;
      case ImportKind.suppliers:
        final other = await (_db.select(_db.supplierLedger)
              ..where((t) =>
                  t.supplierId.equals(id) &
                  (t.type.equals(SupplierLedgerType.opening).not() |
                      t.refId.equals(b.id).not())))
            .get();
        if (other.isNotEmpty) return true;
        final purchases = await (_db.select(_db.purchases)
              ..where((t) => t.supplierId.equals(id)))
            .get();
        return purchases.isNotEmpty;
      default:
        final other = await (_db.select(_db.stockMovements)
              ..where((t) =>
                  t.itemId.equals(id) &
                  (t.reason.equals(StockReason.opening).not() |
                      t.refId.equals(b.id).not())))
            .get();
        if (other.isNotEmpty) return true;
        final sold = await (_db.select(_db.saleLines)
              ..where((t) => t.itemId.equals(id)))
            .get();
        if (sold.isNotEmpty) return true;
        final bought = await (_db.select(_db.purchaseLines)
              ..where((t) => t.itemId.equals(id)))
            .get();
        return bought.isNotEmpty;
    }
  }

  /// Undoes a whole batch: reversing entries for opening balances / stock,
  /// and the created customers, suppliers or items are archived (hidden).
  /// Refused as a whole if any of them has been used since.
  Future<void> undoBatch(String batchId) async {
    final batch = await _batch(batchId);
    if (batch == null) throw const ImportException(ImportError.notFound);
    if (batch.undoneAt != null) {
      throw const ImportException(ImportError.alreadyUndone);
    }
    final shopId = _shopId();
    final now = _now();

    await writeWithOutbox(_db, (outbox) async {
      var blocked = 0;
      for (final id in _ids(batch)) {
        if (await _touched(batch, id)) blocked++;
      }
      if (blocked > 0) {
        throw ImportException(ImportError.undoBlocked, count: blocked);
      }

      for (final id in _ids(batch)) {
        switch (batch.kind) {
          case ImportKind.customers:
            final rows = await (_db.select(_db.customerLedger)
                  ..where((t) => t.customerId.equals(id)))
                .get();
            final amount = rows.fold<int>(0, (s, r) => s + r.amount);
            if (amount != 0) {
              final l = await _db.into(_db.customerLedger).insertReturning(
                    CustomerLedgerCompanion.insert(
                      id: _uuid.v4(),
                      shopId: shopId,
                      customerId: id,
                      type: CustomerLedgerType.adjustment,
                      amount: -amount,
                      refId: Value(batch.id),
                      note: const Value('import undo'),
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
            await (_db.update(_db.customers)..where((t) => t.id.equals(id)))
                .write(CustomersCompanion(
                    isArchived: const Value(true), updatedAt: Value(now)));
            final c = await _db.khataDao.customerById(id);
            if (c != null) {
              outbox.record(table: 'customers', rowId: id, payload: c.toJson());
            }
          case ImportKind.suppliers:
            final rows = await (_db.select(_db.supplierLedger)
                  ..where((t) => t.supplierId.equals(id)))
                .get();
            final amount = rows.fold<int>(0, (s, r) => s + r.amount);
            if (amount != 0) {
              final l = await _db.into(_db.supplierLedger).insertReturning(
                    SupplierLedgerCompanion.insert(
                      id: _uuid.v4(),
                      shopId: shopId,
                      supplierId: id,
                      type: SupplierLedgerType.adjustment,
                      amount: -amount,
                      refId: Value(batch.id),
                      note: const Value('import undo'),
                      date: now,
                      createdAt: now,
                      updatedAt: now,
                    ),
                  );
              outbox.record(
                  table: 'supplier_ledger',
                  rowId: l.id,
                  payload: l.toJson(),
                  op: OutboxOp.insert);
            }
            await (_db.update(_db.suppliers)..where((t) => t.id.equals(id)))
                .write(SuppliersCompanion(
                    isArchived: const Value(true), updatedAt: Value(now)));
            final s = await _db.khataDao.supplierById(id);
            if (s != null) {
              outbox.record(table: 'suppliers', rowId: id, payload: s.toJson());
            }
          default:
            final stock = await _db.inventoryDao.stockOf(id);
            if (stock != 0) {
              final m = await _db.into(_db.stockMovements).insertReturning(
                    StockMovementsCompanion.insert(
                      id: _uuid.v4(),
                      shopId: shopId,
                      itemId: id,
                      qty: -stock,
                      reason: StockReason.adjustment,
                      refType: const Value('import'),
                      refId: Value(batch.id),
                      note: const Value('import undo'),
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
            await (_db.update(_db.items)..where((t) => t.id.equals(id)))
                .write(ItemsCompanion(
                    isArchived: const Value(true), updatedAt: Value(now)));
            final item = await _db.inventoryDao.itemById(id);
            if (item != null) {
              outbox.record(table: 'items', rowId: id, payload: item.toJson());
            }
        }
      }
      await (_db.update(_db.importBatches)..where((t) => t.id.equals(batchId)))
          .write(ImportBatchesCompanion(
              undoneAt: Value(now), updatedAt: Value(now)));
      final b = await _batch(batchId);
      if (b != null) {
        outbox.record(table: 'import_batches', rowId: batchId, payload: b.toJson());
      }
    }, now: () => now);
  }

  Stream<List<ImportBatch>> watchBatches() {
    return (_db.select(_db.importBatches)
          ..where((t) => t.shopId.equals(_shopId()))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Keys of everything already in the shop, for duplicate flags.
  Future<Set<String>> existingPartyKeys(String kind) async {
    final rows = kind == ImportKind.customers
        ? [
            for (final c in await (_db.select(_db.customers)
                  ..where((t) => t.shopId.equals(_shopId())))
                .get())
              partyKey(c.name, c.phone ?? '')
          ]
        : [
            for (final s in await (_db.select(_db.suppliers)
                  ..where((t) => t.shopId.equals(_shopId())))
                .get())
              partyKey(s.name, s.phone ?? '')
          ];
    return rows.toSet();
  }

  Future<({Set<String> names, Set<String> barcodes})> existingItemKeys() async {
    final items = await (_db.select(_db.items)
          ..where((t) => t.shopId.equals(_shopId())))
        .get();
    return (
      names: {for (final i in items) normalizeName(i.name)},
      barcodes: {
        for (final i in items)
          if (i.barcode != null) i.barcode!
      },
    );
  }
}

final importRepositoryProvider = Provider<ImportRepository>((ref) {
  return ImportRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

final importBatchesProvider =
    StreamProvider.autoDispose<List<ImportBatch>>((ref) {
  ref.watch(shopIdProvider);
  return ref.watch(importRepositoryProvider).watchBatches();
});
