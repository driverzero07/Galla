import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/inventory_dao.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';

/// Fields the Saman form edits. Money in paisa, quantities in thousandths.
class ItemInput {
  const ItemInput({
    required this.name,
    this.photoPath,
    this.barcode,
    this.unit = ItemUnit.kg,
    this.costPrice = 0,
    this.salePrice = 0,
    this.lowStockLevel = 0,
  });

  final String name;
  final String? photoPath;
  final String? barcode;
  final String unit;
  final int costPrice;
  final int salePrice;
  final int lowStockLevel;
}

enum ItemError { nameRequired, negativeValue, invalidUnit }

class ItemValidationException implements Exception {
  const ItemValidationException(this.error);
  final ItemError error;
  @override
  String toString() => 'ItemValidationException($error)';
}

/// Another item in this shop already uses the barcode. The UI opens
/// [existingItemId] instead of creating a duplicate.
class DuplicateBarcodeException implements Exception {
  const DuplicateBarcodeException(this.existingItemId);
  final String existingItemId;
  @override
  String toString() => 'DuplicateBarcodeException($existingItemId)';
}

class InventoryRepository {
  InventoryRepository(this._db, this._shopId, this._now);

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  String? _cleanBarcode(String? b) {
    final t = b?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  void _validate(ItemInput i, {int openingStock = 0}) {
    if (i.name.trim().isEmpty) {
      throw const ItemValidationException(ItemError.nameRequired);
    }
    if (i.costPrice < 0 ||
        i.salePrice < 0 ||
        i.lowStockLevel < 0 ||
        openingStock < 0) {
      throw const ItemValidationException(ItemError.negativeValue);
    }
    if (!ItemUnit.all.contains(i.unit)) {
      throw const ItemValidationException(ItemError.invalidUnit);
    }
  }

  Future<void> _checkBarcode(String shopId, String? barcode, {String? selfId}) async {
    if (barcode == null) return;
    final existing = await _db.inventoryDao.itemByBarcode(shopId, barcode);
    if (existing != null && existing.id != selfId) {
      throw DuplicateBarcodeException(existing.id);
    }
  }

  /// Creates an item. A non-zero [openingStock] is recorded as an `opening`
  /// stock movement (stock is never stored on the item). Returns the new id.
  Future<String> createItem(ItemInput input, {int openingStock = 0}) async {
    _validate(input, openingStock: openingStock);
    final shopId = _shopId();
    final barcode = _cleanBarcode(input.barcode);
    final now = _now();
    final id = _uuid.v4();

    await writeWithOutbox(_db, (outbox) async {
      await _checkBarcode(shopId, barcode);
      final item = await _db.into(_db.items).insertReturning(
            ItemsCompanion.insert(
              id: id,
              shopId: shopId,
              name: input.name.trim(),
              photoPath: Value(input.photoPath),
              barcode: Value(barcode),
              unit: Value(input.unit),
              costPrice: Value(input.costPrice),
              salePrice: Value(input.salePrice),
              lowStockLevel: Value(input.lowStockLevel),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'items',
          rowId: item.id,
          payload: item.toJson(),
          op: OutboxOp.insert);

      if (openingStock != 0) {
        final m = await _insertMovement(
          shopId: shopId,
          itemId: id,
          qty: openingStock,
          reason: StockReason.opening,
          now: now,
        );
        outbox.record(
            table: 'stock_movements',
            rowId: m.id,
            payload: m.toJson(),
            op: OutboxOp.insert);
      }
    }, now: () => now);
    return id;
  }

  /// Edits the item's details. Never touches stock; use [adjustStock].
  Future<void> updateItem(String id, ItemInput input) async {
    _validate(input);
    final shopId = _shopId();
    final barcode = _cleanBarcode(input.barcode);
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await _checkBarcode(shopId, barcode, selfId: id);
      final before = await _db.inventoryDao.itemById(id);
      // A new photo has to be uploaded again: forget the old remote link.
      final newPhoto = input.photoPath != null &&
          input.photoPath != before?.photoPath;
      await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
        ItemsCompanion(
          name: Value(input.name.trim()),
          photoPath: Value(input.photoPath),
          photoUrl: newPhoto ? const Value(null) : const Value.absent(),
          barcode: Value(barcode),
          unit: Value(input.unit),
          costPrice: Value(input.costPrice),
          salePrice: Value(input.salePrice),
          lowStockLevel: Value(input.lowStockLevel),
          updatedAt: Value(now),
        ),
      );
      final item = await _db.inventoryDao.itemById(id);
      if (item != null) {
        outbox.record(table: 'items', rowId: id, payload: item.toJson());
      }
    }, now: () => now);
  }

  /// Items are never deleted, only hidden (archived) and shown again.
  Future<void> setArchived(String id, bool archived) async {
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
        ItemsCompanion(isArchived: Value(archived), updatedAt: Value(now)),
      );
      final item = await _db.inventoryDao.itemById(id);
      if (item != null) {
        outbox.record(table: 'items', rowId: id, payload: item.toJson());
      }
    }, now: () => now);
  }

  /// Stock correction: records one `adjustment` movement for the difference
  /// between the current stock and [newCount] (thousandths), with the
  /// owner's [reason]. Does nothing if the count is unchanged.
  Future<void> adjustStock(String itemId, int newCount, String reason) async {
    if (newCount < 0) {
      throw const ItemValidationException(ItemError.negativeValue);
    }
    final shopId = _shopId();
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      final current = await _db.inventoryDao.stockOf(itemId);
      final delta = newCount - current;
      if (delta == 0) return;
      final m = await _insertMovement(
        shopId: shopId,
        itemId: itemId,
        qty: delta,
        reason: StockReason.adjustment,
        note: reason.trim().isEmpty ? null : reason.trim(),
        now: now,
      );
      outbox.record(
          table: 'stock_movements',
          rowId: m.id,
          payload: m.toJson(),
          op: OutboxOp.insert);
    }, now: () => now);
  }

  Future<StockMovement> _insertMovement({
    required String shopId,
    required String itemId,
    required int qty,
    required String reason,
    required DateTime now,
    String? note,
  }) {
    return _db.into(_db.stockMovements).insertReturning(
          StockMovementsCompanion.insert(
            id: _uuid.v4(),
            shopId: shopId,
            itemId: itemId,
            qty: qty,
            reason: reason,
            note: Value(note),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

typedef ItemQuery = ({String query, bool lowOnly, bool showHidden});

final itemListProvider = StreamProvider.autoDispose
    .family<List<ItemWithStock>, ItemQuery>((ref, q) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(appDatabaseProvider).inventoryDao.watchItems(
        shopId,
        query: q.query,
        lowOnly: q.lowOnly,
        includeArchived: q.showHidden,
      );
});

/// Number of visible items at or below their low-stock level.
final lowStockCountProvider = StreamProvider.autoDispose<int>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref
      .watch(appDatabaseProvider)
      .inventoryDao
      .watchItems(shopId, lowOnly: true)
      .map((l) => l.length);
});
