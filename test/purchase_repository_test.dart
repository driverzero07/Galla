import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';
import 'package:galla/features/khata/data/khata_repository.dart';
import 'package:galla/features/purchase/data/purchase_repository.dart';
import 'package:galla/features/purchase/domain/purchase_controller.dart';

void main() {
  late AppDatabase db;
  late PurchaseRepository repo;
  late InventoryRepository inv;
  late KhataRepository khata;
  late String rehman;
  late String cheeni; // cost Rs 165/kg, 5 kg in stock
  late String chai; // cost Rs 380/pack
  final now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await ShopRepository(db).createShop(
        shopId: 'shop1',
        shopName: 'Test Store',
        phone: '+923001234567',
        openingCash: 100000000);
    repo = PurchaseRepository(db, () => 'shop1', () => now, random: Random(3));
    inv = InventoryRepository(db, () => 'shop1', () => now);
    khata = KhataRepository(db, () => 'shop1', () => now);
    rehman = await SupplierRepository(db, () => 'shop1', () => now)
        .create(name: 'Rehman Traders');
    cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000),
        openingStock: 5000);
    chai = await inv.createItem(const ItemInput(
        name: 'Chai patti', unit: ItemUnit.pack, costPrice: 36000));
  });
  tearDown(() => db.close());

  Future<int> stock(String id) => db.inventoryDao.stockOf(id);
  Future<int> dena() => db.khataDao.supplierBalance(rehman);

  PurchaseLineInput line(String id, int qty, int cost) =>
      PurchaseLineInput(itemId: id, qty: qty, unitCost: cost);

  test('totals: Rs 165 x 50 kg + Rs 380 x 20 pack', () {
    final i = PurchaseInput(supplierId: rehman, lines: [
      line(cheeni, 50000, 16500),
      line(chai, 20000, 38000),
    ]);
    expect(i.total, 825000 + 760000);
  });

  test('line total rounds like bills (2.5 kg x Rs 165.10)', () {
    expect(line(cheeni, 2500, 16510).total, 41275);
  });

  group('savePurchase', () {
    test('raises stock, supplier balance and cost together', () async {
      final saved = await repo.savePurchase(PurchaseInput(
        supplierId: rehman,
        lines: [line(cheeni, 50000, 17000), line(chai, 20000, 38000)],
        paidNow: 1000000,
      ));
      expect(saved.total, 850000 + 760000);
      expect(saved.unpaid, 1610000 - 1000000);
      expect(await stock(cheeni), 55000);
      expect(await stock(chai), 20000);
      expect(await dena(), 610000);
      expect((await db.inventoryDao.itemById(cheeni))!.costPrice, 17000);
      expect((await db.inventoryDao.itemById(chai))!.costPrice, 38000);
      // sale price untouched
      expect((await db.inventoryDao.itemById(cheeni))!.salePrice, 18000);
    });

    test('fully paid purchase writes no supplier ledger row', () async {
      await repo.savePurchase(PurchaseInput(
          supplierId: rehman,
          lines: [line(cheeni, 1000, 16500)],
          paidNow: 16500));
      expect(await dena(), 0);
      expect(await db.select(db.supplierLedger).get(), isEmpty);
      final p = (await db.select(db.purchases).get()).single;
      expect(p.paidAmount, 16500);
    });

    test('paid more than total is capped at the total', () async {
      final saved = await repo.savePurchase(PurchaseInput(
          supplierId: rehman,
          lines: [line(cheeni, 1000, 16500)],
          paidNow: 99999999));
      expect(saved.unpaid, 0);
      expect((await db.select(db.purchases).get()).single.paidAmount, 16500);
    });

    test('nothing paid: whole total is owed', () async {
      await repo.savePurchase(PurchaseInput(
          supplierId: rehman, lines: [line(cheeni, 2000, 16500)]));
      expect(await dena(), 33000);
      final l = (await db.select(db.supplierLedger).get()).single;
      expect(l.type, SupplierLedgerType.purchaseCredit);
      expect(l.amount, 33000);
      expect(l.refId, (await db.select(db.purchases).get()).single.id);
    });

    test('lines and positive stock movements reference the purchase',
        () async {
      final saved = await repo.savePurchase(PurchaseInput(
          supplierId: rehman, lines: [line(cheeni, 2000, 16500)]));
      final lines = await db.purchasesDao.linesOf(saved.purchaseId);
      expect(lines.single.qty, 2000);
      expect(lines.single.unitCost, 16500);
      final m = (await (db.select(db.stockMovements)
                ..where((t) => t.reason.equals(StockReason.purchase)))
              .get())
          .single;
      expect(m.qty, 2000);
      expect(m.refType, 'purchase');
      expect(m.refId, saved.purchaseId);
    });

    test('invoice photo path is kept', () async {
      final saved = await repo.savePurchase(PurchaseInput(
          supplierId: rehman,
          lines: [line(cheeni, 1000, 16500)],
          invoiceImagePath: '/photos/a.jpg'));
      final p = await db.purchasesDao.purchaseById(saved.purchaseId);
      expect(p!.invoiceImagePath, '/photos/a.jpg');
    });

    test('purchase numbers increment with a stable prefix', () async {
      final a = await repo.savePurchase(
          PurchaseInput(supplierId: rehman, lines: [line(cheeni, 1000, 1)]));
      final b = await repo.savePurchase(
          PurchaseInput(supplierId: rehman, lines: [line(cheeni, 1000, 1)]));
      expect(a.purchaseNo.split('-').first, b.purchaseNo.split('-').first);
      expect(int.parse(b.purchaseNo.split('-').last),
          int.parse(a.purchaseNo.split('-').last) + 1);
    });

    test('outbox has every touched table', () async {
      await repo.savePurchase(PurchaseInput(
          supplierId: rehman, lines: [line(cheeni, 1000, 17000)]));
      final tables =
          (await db.select(db.outbox).get()).map((o) => o.entityTable).toSet();
      expect(
          tables,
          containsAll([
            'purchases',
            'purchase_lines',
            'stock_movements',
            'supplier_ledger',
            'items'
          ]));
    });

    test('failure rolls everything back, number not burned', () async {
      await expectLater(
          repo.savePurchase(PurchaseInput(
              supplierId: rehman,
              lines: [line(cheeni, 1000, 17000), line('nope', 1000, 1)])),
          throwsA(isA<PurchaseException>()
              .having((e) => e.error, 'e', PurchaseError.unknownItem)));
      expect(await db.select(db.purchases).get(), isEmpty);
      expect(await db.select(db.purchaseLines).get(), isEmpty);
      expect(await stock(cheeni), 5000);
      expect((await db.inventoryDao.itemById(cheeni))!.costPrice, 16500);
      expect(await dena(), 0);
      final ok = await repo.savePurchase(
          PurchaseInput(supplierId: rehman, lines: [line(cheeni, 1000, 1)]));
      expect(ok.purchaseNo.split('-').last, '1');
    });

    test('validation', () async {
      Matcher err(PurchaseError e) =>
          throwsA(isA<PurchaseException>().having((x) => x.error, 'e', e));
      await expectLater(
          repo.savePurchase(PurchaseInput(supplierId: rehman, lines: const [])),
          err(PurchaseError.empty));
      await expectLater(
          repo.savePurchase(
              PurchaseInput(supplierId: rehman, lines: [line(cheeni, 0, 1)])),
          err(PurchaseError.badQuantity));
      await expectLater(
          repo.savePurchase(
              PurchaseInput(supplierId: rehman, lines: [line(cheeni, 1000, -1)])),
          err(PurchaseError.badCost));
      await expectLater(
          repo.savePurchase(PurchaseInput(
              supplierId: rehman,
              lines: [line(cheeni, 1000, 1), line(cheeni, 1000, 1)])),
          err(PurchaseError.duplicateItem));
      await expectLater(
          repo.savePurchase(PurchaseInput(
              supplierId: 'nope', lines: [line(cheeni, 1000, 1)])),
          err(PurchaseError.unknownSupplier));
      await expectLater(
          repo.savePurchase(PurchaseInput(
              supplierId: rehman, lines: [line(cheeni, 1000, 1)], paidNow: -5)),
          err(PurchaseError.badPaid));
    });
  });

  test('supplier history shows purchase with items and paid amount, then '
      'payments; balance = SUM', () async {
    await repo.savePurchase(PurchaseInput(
        supplierId: rehman,
        lines: [line(cheeni, 1000, 17000), line(chai, 1000, 38000)],
        paidNow: 10000));
    await khata.paySupplier(rehman, 20000);
    final h = await khata.supplierHistory(rehman);
    expect(h.balance, 55000 - 10000 - 20000);
    expect(h.balance, await dena());
    final purchase = h.entries
        .firstWhere((e) => e.type == SupplierLedgerType.purchaseCredit);
    expect(purchase.itemsText, 'Cheeni, Chai patti');
    expect(purchase.paidNote, 10000);
    expect(purchase.amount, 45000);
    expect(h.entries.first.type, SupplierLedgerType.paymentMade);
  });

  test('detail and list queries', () async {
    final saved = await repo.savePurchase(PurchaseInput(
        supplierId: rehman, lines: [line(cheeni, 1000, 17000)]));
    final d = await db.purchasesDao.detail(saved.purchaseId);
    expect(d!.supplierName, 'Rehman Traders');
    expect(d.lines.single.itemName, 'Cheeni');
    final list = await db.purchasesDao.watchPurchases('shop1').first;
    expect(list.single.supplierName, 'Rehman Traders');
  });

  group('PurchaseController', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    Future<Item> item(String id) async => (await db.inventoryDao.itemById(id))!;

    test('add uses last cost; adding again increases qty; totals derived',
        () async {
      final n = c.read(purchaseControllerProvider.notifier);
      n.addItem(await item(cheeni), qty: 2000);
      n.addItem(await item(cheeni), qty: 1000);
      n.addItem(await item(chai));
      var d = c.read(purchaseControllerProvider);
      expect(d.lines, hasLength(2));
      expect(d.lines.first.qty, 3000);
      expect(d.lines.first.unitCost, 16500);
      expect(d.total, 49500 + 36000);
      n.setCost(cheeni, 17000);
      n.setPaidNow(1000000);
      d = c.read(purchaseControllerProvider);
      expect(d.total, 51000 + 36000);
      expect(d.effectivePaid, d.total);
      expect(d.unpaid, 0);
      n.setPaidNow(40000);
      expect(c.read(purchaseControllerProvider).unpaid, 87000 - 40000);
    });

    test('quantity zero removes the line; clear resets', () async {
      final n = c.read(purchaseControllerProvider.notifier);
      n.addItem(await item(cheeni));
      n.setQty(cheeni, 0);
      expect(c.read(purchaseControllerProvider).lines, isEmpty);
      n.setSupplier(rehman, 'Rehman');
      expect(c.read(purchaseControllerProvider).isEmpty, isFalse);
      n.clear();
      expect(c.read(purchaseControllerProvider).isEmpty, isTrue);
    });

    test('toInput saves through the repository', () async {
      final n = c.read(purchaseControllerProvider.notifier);
      n.setSupplier(rehman, 'Rehman');
      n.addItem(await item(cheeni), qty: 2000);
      n.setPaidNow(10000);
      final saved =
          await repo.savePurchase(c.read(purchaseControllerProvider).toInput());
      expect(saved.total, 33000);
      expect(await dena(), 23000);
    });
  });
}
