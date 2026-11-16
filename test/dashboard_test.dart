import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/db/daos/inventory_dao.dart';
import 'package:galla/core/utils/day_start.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/auth/domain/auth_controller.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/home/domain/dashboard.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';

Item _item(String name) => Item(
      id: name,
      shopId: 's',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isArchived: false,
      name: name,
      photoPath: null,
      photoUrl: null,
      barcode: null,
      unit: 'kg',
      costPrice: 0,
      salePrice: 0,
      lowStockLevel: 0,
    );

ItemWithStock _low(String name, int stock) => ItemWithStock(_item(name), stock);

void main() {
  group('TodaySummary', () {
    test('cash + udhaar = total; profit = total - cost', () {
      const s = TodaySummary(bills: 3, total: 101000, paid: 60000, cost: 89750);
      expect(s.cash, 60000);
      expect(s.udhaar, 41000);
      expect(s.cash + s.udhaar, s.total);
      expect(s.profit, 11250);
    });

    test('empty day is all zero', () {
      const s = TodaySummary();
      expect((s.total, s.cash, s.udhaar, s.profit), (0, 0, 0, 0));
    });

    test('a loss shows as negative profit', () {
      const s = TodaySummary(total: 1000, paid: 1000, cost: 1500);
      expect(s.profit, -500);
    });

    test('line cost rounds half up like bills', () {
      expect(costOfLine(2500, 16500), 41250);
      expect(costOfLine(1, 500), 1);
      expect(costOfLine(1, 499), 0);
    });
  });

  group('days', () {
    test('dayRange is local midnight to midnight', () {
      final r = dayRange(DateTime(2026, 11, 14, 15, 30));
      expect(r.from, DateTime(2026, 11, 14));
      expect(r.to, DateTime(2026, 11, 15));
      expect(dayRange(DateTime(2026, 11, 30, 23, 59)).to, DateTime(2026, 12, 1));
      expect(dayRange(DateTime(2026, 12, 31, 12)).to, DateTime(2027, 1, 1));
    });

    test('untilNextDay counts down to midnight and is never zero', () {
      expect(untilNextDay(DateTime(2026, 11, 14, 23, 59, 30)),
          const Duration(seconds: 30));
      expect(untilNextDay(DateTime(2026, 11, 14)), const Duration(days: 1));
    });

    testWidgets('dayStartProvider rolls over at midnight', (tester) async {
      var now = DateTime(2026, 11, 14, 23, 59, 30);
      final c = ProviderContainer(
          overrides: [clockProvider.overrideWithValue(() => now)]);
      final seen = <DateTime>[];
      c.listen(dayStartProvider, (_, n) => n.whenData(seen.add),
          fireImmediately: true);
      await tester.pump();
      expect(seen, [DateTime(2026, 11, 14)]);

      now = DateTime(2026, 11, 15, 0, 0, 5);
      await tester.pump(const Duration(seconds: 40));
      expect(seen.last, DateTime(2026, 11, 15));
      c.dispose();
      await tester.pump();
    });
  });

  group('alerts', () {
    test('lowest 3: least stock first, negative first, then name', () {
      final top = lowestStock([
        _low('Daal', 3000),
        _low('Cheeni', -500),
        _low('Atta', 3000),
        _low('Chai', 1000),
      ]);
      expect(top.map((e) => e.item.name), ['Cheeni', 'Chai', 'Atta']);
    });

    test('low items and offline sync problem build alerts', () {
      final alerts = buildAlerts(
          lowItems: [_low('A', 0), _low('B', 0)], online: false, pending: 4);
      expect(alerts, hasLength(2));
      expect(alerts[0], isA<LowStockAlert>());
      expect(alerts[1], isA<SyncAlert>());
      expect(alertCount(alerts), 3);
    });

    test('pending changes while online are not an alert', () {
      expect(buildAlerts(lowItems: const [], online: true, pending: 9), isEmpty);
    });

    test('offline with nothing pending is not an alert', () {
      expect(buildAlerts(lowItems: const [], online: false, pending: 0),
          isEmpty);
    });
  });

  group('live queries on seeded data', () {
    late AppDatabase db;
    late SalesRepository sales;
    late String cheeni; // cost Rs 165/kg, price Rs 180
    late String atta; // cost Rs 80, price Rs 100
    late String ali;
    var now = DateTime(2026, 11, 14, 10);
    final from = DateTime(2026, 11, 14);
    final to = DateTime(2026, 11, 15);

    setUp(() async {
      now = DateTime(2026, 11, 14, 10);
      db = AppDatabase(NativeDatabase.memory());
      await ShopRepository(db).createShop(
          shopId: 'shop1', shopName: 'Test Store', phone: '+923001234567');
      sales = SalesRepository(db, () => 'shop1', () => now);
      final inv = InventoryRepository(db, () => 'shop1', () => now);
      cheeni = await inv.createItem(
          const ItemInput(
              name: 'Cheeni',
              unit: ItemUnit.kg,
              costPrice: 16500,
              salePrice: 18000,
              lowStockLevel: 5000),
          openingStock: 100000);
      atta = await inv.createItem(
          const ItemInput(
              name: 'Atta',
              unit: ItemUnit.piece,
              costPrice: 8000,
              salePrice: 10000),
          openingStock: 100000);
      ali = await CustomerRepository(db, () => 'shop1', () => now)
          .create(name: 'Ali');
    });
    tearDown(() => db.close());

    BillLineInput line(String id, int qty, int price) =>
        BillLineInput(itemId: id, qty: qty, unitPrice: price);

    Future<({int bills, int total, int paid, int cost})> today() =>
        db.salesDao.watchDaySummary('shop1', from, to).first;

    test('no bills: zeros', () async {
      final s = await today();
      expect((s.bills, s.total, s.paid, s.cost), (0, 0, 0, 0));
    });

    test('matches a manual calculation', () async {
      // A: cash. 2.5 kg Cheeni @180 = 450 (cost 412.50) + 1 Atta @100 (cost 80)
      await sales.saveBill(BillInput(
          lines: [line(cheeni, 2500, 18000), line(atta, 1000, 10000)]));
      // B: udhaar to Ali. 3 Atta @100 = 300, discount 20 -> 280 (cost 240)
      await sales.saveBill(BillInput(
          lines: [line(atta, 3000, 10000)],
          discount: 2000,
          customerId: ali,
          credit: true));
      // C: partial. 1 kg Cheeni @180, paid 50 (cost 165)
      await sales.saveBill(BillInput(
          lines: [line(cheeni, 1000, 18000)],
          customerId: ali,
          credit: true,
          paidNow: 5000));
      // D: cancelled, must not count.
      final d = await sales.saveBill(
          BillInput(lines: [line(cheeni, 4000, 18000)]));
      await sales.cancelSale(d.saleId);

      final s = await today();
      final summary =
          TodaySummary(bills: s.bills, total: s.total, paid: s.paid, cost: s.cost);
      expect(summary.bills, 3);
      expect(summary.total, 55000 + 28000 + 18000); // Rs 1,010
      expect(summary.cash, 55000 + 0 + 5000); // Rs 600
      expect(summary.udhaar, 28000 + 13000); // Rs 410
      expect(summary.cost, 49250 + 24000 + 16500); // Rs 897.50
      expect(summary.profit, 11250); // Rs 112.50
    });

    test('yesterday and tomorrow are excluded; midnight is included',
        () async {
      now = DateTime(2026, 11, 13, 23, 59, 59);
      await sales.saveBill(BillInput(lines: [line(atta, 1000, 10000)]));
      now = DateTime(2026, 11, 14, 0, 0, 0);
      await sales.saveBill(BillInput(lines: [line(atta, 2000, 10000)]));
      now = DateTime(2026, 11, 15, 0, 0, 0);
      await sales.saveBill(BillInput(lines: [line(atta, 4000, 10000)]));
      final s = await today();
      expect(s.bills, 1);
      expect(s.total, 20000);
    });

    test('price changes later do not alter an old bill\'s profit', () async {
      await sales.saveBill(BillInput(lines: [line(atta, 1000, 10000)]));
      await InventoryRepository(db, () => 'shop1', () => now).updateItem(
          atta,
          const ItemInput(
              name: 'Atta',
              unit: ItemUnit.piece,
              costPrice: 9500,
              salePrice: 12000));
      final s = await today();
      expect(s.total - s.cost, 2000);
    });

    test('updates the moment a bill is saved', () async {
      final totals = <int>[];
      final sub = db.salesDao
          .watchDaySummary('shop1', from, to)
          .listen((e) => totals.add(e.total));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(totals.last, 0);
      await sales.saveBill(BillInput(lines: [line(atta, 1000, 10000)]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(totals.last, 10000);
      final saved = await sales.saveBill(
          BillInput(lines: [line(atta, 1000, 10000)]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(totals.last, 20000);
      await sales.cancelSale(saved.saleId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(totals.last, 10000);
      await sub.cancel();
    });

    test('low stock list follows stock live', () async {
      final lows = <List<String>>[];
      final sub = db.inventoryDao
          .watchItems('shop1', lowOnly: true)
          .listen((l) => lows.add([for (final e in l) e.item.name]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(lows.last, isEmpty);
      // Cheeni level is 5 kg; selling 96 kg leaves 4 kg.
      await sales.saveBill(BillInput(lines: [line(cheeni, 96000, 18000)]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(lows.last, ['Cheeni']);
      expect(lowestStock(await db.inventoryDao
              .watchItems('shop1', lowOnly: true)
              .first)
          .single
          .stock, 4000);
      await sub.cancel();
    });
  });
}
