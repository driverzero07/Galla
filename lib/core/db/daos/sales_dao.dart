import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'sales_dao.g.dart';

class SaleListRow {
  const SaleListRow(this.sale, this.customerName);
  final Sale sale;
  final String customerName;
}

class SaleDetailData {
  const SaleDetailData({
    required this.sale,
    required this.lines,
    required this.customerName,
    required this.returns,
    required this.returnedQty,
    this.units = const {},
  });

  final Sale sale;
  final List<SaleLine> lines;
  final String customerName;
  final List<SaleReturn> returns;

  /// item id -> total quantity already returned (thousandths).
  final Map<String, int> returnedQty;

  /// item id -> unit (kg, pack...) for display; items are never deleted.
  final Map<String, String> units;

  String unitOf(String itemId) => units[itemId] ?? '';

  int returnableQty(SaleLine line) =>
      line.qty - (returnedQty[line.itemId] ?? 0);

  bool get canReturn =>
      sale.status == 'active' && lines.any((l) => returnableQty(l) > 0);
}

@DriftAccessor(
  tables: [Sales, SaleLines, SaleReturns, SaleReturnLines, Customers, Items],
)
class SalesDao extends DatabaseAccessor<AppDatabase> with _$SalesDaoMixin {
  SalesDao(super.db);

  Future<Sale?> saleById(String id) =>
      (select(sales)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<SaleLine>> linesOf(String saleId) =>
      (select(saleLines)..where((t) => t.saleId.equals(saleId))).get();

  Future<List<SaleReturn>> returnsOf(String saleId) =>
      (select(saleReturns)..where((t) => t.saleId.equals(saleId))).get();

  /// Quantity already returned per item for this sale.
  Future<Map<String, int>> returnedQtyByItem(String saleId) async {
    final rows = await customSelect(
      'SELECT item_id, SUM(qty) AS q FROM sale_return_lines '
      'WHERE sale_id = ?1 GROUP BY item_id',
      variables: [Variable.withString(saleId)],
      readsFrom: {saleReturnLines},
    ).get();
    return {
      for (final r in rows) r.read<String>('item_id'): r.read<int>('q'),
    };
  }

  Future<SaleDetailData?> saleDetail(String saleId) async {
    final sale = await saleById(saleId);
    if (sale == null) return null;
    final customer = await (select(customers)
          ..where((t) => t.id.equals(sale.customerId)))
        .getSingleOrNull();
    final lines = await linesOf(saleId);
    final itemRows = lines.isEmpty
        ? <Item>[]
        : await (select(items)
              ..where((t) => t.id.isIn(lines.map((l) => l.itemId))))
            .get();
    return SaleDetailData(
      sale: sale,
      lines: lines,
      units: {for (final i in itemRows) i.id: i.unit},
      customerName: customer?.name ?? '',
      returns: await returnsOf(saleId),
      returnedQty: await returnedQtyByItem(saleId),
    );
  }

  /// Bills created in [from, to), newest first.
  Stream<List<SaleListRow>> watchSalesBetween(
      String shopId, DateTime from, DateTime to) {
    final query = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
    ])
      ..where(sales.shopId.equals(shopId) &
          sales.createdAt.isBiggerOrEqualValue(from) &
          sales.createdAt.isSmallerThanValue(to))
      ..orderBy([OrderingTerm.desc(sales.createdAt)]);
    return query.watch().map((rows) => [
          for (final r in rows)
            SaleListRow(
                r.readTable(sales), r.readTableOrNull(customers)?.name ?? ''),
        ]);
  }

  /// Stock per item (thousandths); items with no movements map to 0.
  Future<Map<String, int>> stocksOf(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await customSelect(
      'SELECT item_id, SUM(qty) AS s FROM stock_movements '
      'WHERE item_id IN (${List.filled(ids.length, '?').join(',')}) '
      'GROUP BY item_id',
      variables: [for (final id in ids) Variable.withString(id)],
      readsFrom: {db.stockMovements},
    ).get();
    final result = {for (final id in ids) id: 0};
    for (final r in rows) {
      result[r.read<String>('item_id')] = r.read<int>('s');
    }
    return result;
  }

  /// The [limit] best-selling visible items since [since] (by number of
  /// bill lines, then quantity), from active bills. If fewer than [limit]
  /// items have sales, the rest are filled alphabetically so the grid is
  /// never empty on day one.
  Future<List<Item>> quickPickItems(String shopId, DateTime since,
      {int limit = 8}) async {
    final rows = await customSelect(
      'SELECT i.* FROM items i LEFT JOIN ('
      'SELECT sl.item_id AS item_id, COUNT(*) AS c, SUM(sl.qty) AS q '
      'FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id '
      "WHERE s.shop_id = ?1 AND s.status = 'active' AND s.created_at >= ?2 "
      'GROUP BY sl.item_id) t ON t.item_id = i.id '
      'WHERE i.shop_id = ?1 AND i.is_archived = 0 '
      'ORDER BY COALESCE(t.c, 0) DESC, COALESCE(t.q, 0) DESC, '
      'i.name COLLATE NOCASE LIMIT ?3',
      variables: [
        Variable.withString(shopId),
        Variable.withDateTime(since),
        Variable.withInt(limit),
      ],
      readsFrom: {items, sales, saleLines},
    ).get();
    return [for (final r in rows) items.map(r.data)];
  }

  /// Live numbers for Home: active bills in [from, to). Re-runs whenever a
  /// bill, its lines or a cancellation changes.
  Stream<({int bills, int total, int paid, int cost})> watchDaySummary(
      String shopId, DateTime from, DateTime to) {
    return customSelect(
      'SELECT COUNT(*) AS bills, '
      'COALESCE(SUM(s.total), 0) AS total, '
      'COALESCE(SUM(s.paid_amount), 0) AS paid, '
      'COALESCE(SUM((SELECT SUM((l.qty * l.cost_snapshot + 500) / 1000) '
      'FROM sale_lines l WHERE l.sale_id = s.id)), 0) AS cost '
      "FROM sales s WHERE s.shop_id = ?1 AND s.status = 'active' "
      'AND s.created_at >= ?2 AND s.created_at < ?3',
      variables: [
        Variable.withString(shopId),
        Variable.withDateTime(from),
        Variable.withDateTime(to),
      ],
      readsFrom: {sales, saleLines},
    ).watchSingle().map((r) => (
          bills: r.read<int>('bills'),
          total: r.read<int>('total'),
          paid: r.read<int>('paid'),
          cost: r.read<int>('cost'),
        ));
  }
}
