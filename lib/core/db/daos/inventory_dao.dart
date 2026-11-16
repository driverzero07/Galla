import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'inventory_dao.g.dart';

/// An item with its derived stock (SUM of movements, thousandths).
class ItemWithStock {
  const ItemWithStock(this.item, this.stock);
  final Item item;
  final int stock;

  /// Part 0 rule 10: low stock means stock is at or below the item's level.
  bool get isLow => stock <= item.lowStockLevel;
}

/// Turns user text into an FTS5 prefix query (`che` -> `"che"*`). Returns an
/// empty string when there is nothing searchable. Only letters and digits
/// survive, so user input can never break the query syntax.
String ftsPrefixQuery(String input) => input
    .split(RegExp(r'\s+'))
    .map((t) => t.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
    .where((t) => t.isNotEmpty)
    .map((t) => '"$t"*')
    .join(' ');

@DriftAccessor(tables: [Items, StockMovements])
class InventoryDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryDaoMixin {
  InventoryDao(super.db);

  Future<Item?> itemById(String id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Item?> itemByBarcode(String shopId, String barcode) {
    return (select(items)
          ..where((t) => t.shopId.equals(shopId) & t.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  /// Stock is always derived: SUM(stock_movements.qty). Never stored.
  Future<int> stockOf(String itemId) async {
    final sum = stockMovements.qty.sum();
    final row = await (selectOnly(stockMovements)
          ..addColumns([sum])
          ..where(stockMovements.itemId.equals(itemId)))
        .getSingle();
    return row.read(sum) ?? 0;
  }

  Stream<int> watchStockOf(String itemId) {
    final sum = stockMovements.qty.sum();
    return (selectOnly(stockMovements)
          ..addColumns([sum])
          ..where(stockMovements.itemId.equals(itemId)))
        .map((row) => row.read(sum) ?? 0)
        .watchSingle();
  }

  /// Full-text name search (FTS5 prefix match), e.g. `che` finds `Cheeni`.
  Future<List<String>> searchItemIds(String shopId, String query,
      {int limit = 50}) async {
    final terms = ftsPrefixQuery(query);
    if (terms.isEmpty) return const [];
    final rows = await customSelect(
      'SELECT i.id AS id FROM items_fts f '
      'JOIN items i ON i.rowid = f.rowid '
      'WHERE items_fts MATCH ?1 AND i.shop_id = ?2 '
      'ORDER BY rank LIMIT ?3',
      variables: [
        Variable.withString(terms),
        Variable.withString(shopId),
        Variable.withInt(limit),
      ],
      readsFrom: {items},
    ).get();
    return [for (final r in rows) r.read<String>('id')];
  }

  /// Live item list with derived stock, sorted by name. Hidden (archived)
  /// items are left out unless [includeArchived]. [query] is a full-text
  /// name search; [lowOnly] keeps items at or below their low-stock level.
  Stream<List<ItemWithStock>> watchItems(
    String shopId, {
    String query = '',
    bool lowOnly = false,
    bool includeArchived = false,
  }) {
    final vars = <Variable>[Variable.withString(shopId)];
    final sql = StringBuffer(
      'SELECT t.* FROM (SELECT i.*, COALESCE((SELECT SUM(m.qty) '
      'FROM stock_movements m WHERE m.item_id = i.id), 0) AS stock '
      'FROM items i WHERE i.shop_id = ?1',
    );
    if (!includeArchived) sql.write(' AND i.is_archived = 0');
    final terms = ftsPrefixQuery(query);
    if (terms.isNotEmpty) {
      vars.add(Variable.withString(terms));
      sql.write(' AND i.rowid IN (SELECT rowid FROM items_fts '
          'WHERE items_fts MATCH ?${vars.length})');
    }
    sql.write(') t');
    if (lowOnly) sql.write(' WHERE t.stock <= t.low_stock_level');
    sql.write(' ORDER BY t.name COLLATE NOCASE');
    return customSelect(
      sql.toString(),
      variables: vars,
      readsFrom: {items, stockMovements},
    ).watch().map((rows) => [
          for (final r in rows)
            ItemWithStock(items.map(r.data), r.read<int>('stock')),
        ]);
  }
}
