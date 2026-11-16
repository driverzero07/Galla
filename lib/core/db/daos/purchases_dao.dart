import 'package:drift/drift.dart';

import '../app_database.dart';
import '../constants.dart';
import '../tables.dart';

part 'purchases_dao.g.dart';

/// A purchase with the supplier name, for lists.
class PurchaseListRow {
  const PurchaseListRow(this.purchase, this.supplierName);
  final Purchase purchase;
  final String supplierName;
}

/// Short text for ledger history rows.
class PurchaseBrief {
  const PurchaseBrief({
    required this.purchase,
    required this.itemNames,
  });
  final Purchase purchase;
  final List<String> itemNames;
}

class PurchaseLineView {
  const PurchaseLineView(this.line, this.itemName, this.unit);
  final PurchaseLine line;
  final String itemName;
  final String unit;
}

class PurchaseDetailData {
  const PurchaseDetailData(this.purchase, this.supplierName, this.lines);
  final Purchase purchase;
  final String supplierName;
  final List<PurchaseLineView> lines;
}

@DriftAccessor(tables: [Purchases, PurchaseLines, Suppliers, Items])
class PurchasesDao extends DatabaseAccessor<AppDatabase>
    with _$PurchasesDaoMixin {
  PurchasesDao(super.db);

  Future<Purchase?> purchaseById(String id) =>
      (select(purchases)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<PurchaseLine>> linesOf(String purchaseId) =>
      (select(purchaseLines)..where((t) => t.purchaseId.equals(purchaseId)))
          .get();

  Future<PurchaseDetailData?> detail(String id) async {
    final p = await purchaseById(id);
    if (p == null) return null;
    final supplier = await db.khataDao.supplierById(p.supplierId);
    final lines = await linesOf(id);
    final views = <PurchaseLineView>[];
    for (final l in lines) {
      final item = await db.inventoryDao.itemById(l.itemId);
      views.add(PurchaseLineView(
          l, item?.name ?? '?', item?.unit ?? ItemUnit.kg));
    }
    return PurchaseDetailData(p, supplier?.name ?? '', views);
  }

  /// Newest first. [supplierId] null = every supplier.
  Stream<List<PurchaseListRow>> watchPurchases(String shopId,
      {String? supplierId}) {
    final q = select(purchases).join([
      leftOuterJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])
      ..where(purchases.shopId.equals(shopId))
      ..orderBy([OrderingTerm.desc(purchases.createdAt)]);
    if (supplierId != null) {
      q.where(purchases.supplierId.equals(supplierId));
    }
    return q.watch().map((rows) => [
          for (final r in rows)
            PurchaseListRow(
              r.readTable(purchases),
              r.readTableOrNull(suppliers)?.name ?? '',
            ),
        ]);
  }

  /// Item names per purchase id, in line order, for history rows.
  Future<Map<String, PurchaseBrief>> briefs(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final ps = await (select(purchases)..where((t) => t.id.isIn(list))).get();
    final q = select(purchaseLines).join([
      innerJoin(items, items.id.equalsExp(purchaseLines.itemId)),
    ])
      ..where(purchaseLines.purchaseId.isIn(list))
      ..orderBy([OrderingTerm.asc(purchaseLines.createdAt)]);
    final names = <String, List<String>>{};
    for (final r in await q.get()) {
      names
          .putIfAbsent(r.readTable(purchaseLines).purchaseId, () => [])
          .add(r.readTable(items).name);
    }
    return {
      for (final p in ps)
        p.id: PurchaseBrief(purchase: p, itemNames: names[p.id] ?? const []),
    };
  }
}
