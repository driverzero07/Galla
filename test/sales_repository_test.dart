import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  late InventoryRepository inv;
  late CustomerRepository customers;
  late String cheeni; // Rs 180 / kg, cost 165, 50 kg
  late String atta; // Rs 100 each, cost 80, 10
  late String ali;
  var now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await ShopRepository(db).createShop(
        shopId: 'shop1', shopName: 'Test Store', phone: '+923001234567');
    sales = SalesRepository(db, () => 'shop1', () => now, random: Random(1));
    inv = InventoryRepository(db, () => 'shop1', () => now);
    customers = CustomerRepository(db, () => 'shop1', () => now);
    cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000),
        openingStock: 50000);
    atta = await inv.createItem(
        const ItemInput(
            name: 'Atta', unit: ItemUnit.piece, costPrice: 8000, salePrice: 10000),
        openingStock: 10000);
    ali = await customers.create(name: 'Ali');
  });
  tearDown(() => db.close());

  Future<int> stock(String id) => db.inventoryDao.stockOf(id);
  Future<int> owed(String id) => db.khataDao.customerBalance(id);
  BillLineInput line(String id, int qty, int price) =>
      BillLineInput(itemId: id, qty: qty, unitPrice: price);

  group('saveBill', () {
    test('cash sale: sale, lines, negative stock, no ledger', () async {
      final saved = await sales.saveBill(BillInput(lines: [
        line(cheeni, 2500, 18000),
        line(atta, 1000, 10000),
      ]));
      final sale = await db.salesDao.saleById(saved.saleId);
      expect(sale!.subtotal, 55000);
      expect(sale.total, 55000);
      expect(sale.paidAmount, 55000);
      expect(sale.paymentMode, PaymentMode.cash);
      final lines = await db.salesDao.linesOf(saved.saleId);
      expect(lines, hasLength(2));
      expect(await stock(cheeni), 47500);
      expect(await stock(atta), 9000);
      expect(await db.select(db.customerLedger).get(), isEmpty);
    });

    test('udhaar: whole total goes to khata', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 1000, 18000)], customerId: ali, credit: true));
      expect(await owed(ali), 18000);
      final sale = await db.salesDao.saleById(saved.saleId);
      expect(sale!.paymentMode, PaymentMode.udhaar);
      expect(sale.paidAmount, 0);
    });

    test('partial: only the unpaid part goes to khata', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 1000, 18000)],
          customerId: ali,
          credit: true,
          paidNow: 5000));
      expect(await owed(ali), 13000);
      final sale = await db.salesDao.saleById(saved.saleId);
      expect(sale!.paymentMode, PaymentMode.partial);
      expect(sale.paidAmount, 5000);
    });

    test('discount reduces total; too-high discount is rejected', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 1000, 18000)], discount: 3000));
      expect((await db.salesDao.saleById(saved.saleId))!.total, 15000);
      await expectLater(
          sales.saveBill(BillInput(
              lines: [line(cheeni, 1000, 18000)], discount: 18001)),
          throwsA(isA<BillException>()
              .having((e) => e.error, 'error', BillError.discountTooHigh)));
    });

    test('price override applies to this bill only; snapshots kept',
        () async {
      final saved =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 17000)]));
      final item = await db.inventoryDao.itemById(cheeni);
      expect(item!.salePrice, 18000);
      final l = (await db.salesDao.linesOf(saved.saleId)).single;
      expect(l.unitPrice, 17000);
      expect(l.nameSnapshot, 'Cheeni');
      expect(l.costSnapshot, 16500);

      await inv.updateItem(
          cheeni,
          const ItemInput(
              name: 'Cheeni 2',
              unit: ItemUnit.kg,
              costPrice: 20000,
              salePrice: 25000));
      final again = (await db.salesDao.linesOf(saved.saleId)).single;
      expect(again.unitPrice, 17000);
      expect(again.nameSnapshot, 'Cheeni');
      expect(again.costSnapshot, 16500);
    });

    test('selling more than stock is allowed (negative stock)', () async {
      await sales.saveBill(BillInput(lines: [line(atta, 15000, 10000)]));
      expect(await stock(atta), -5000);
    });

    test('shortages reports items beyond stock', () async {
      final s = await sales.shortages([line(atta, 15000, 10000)]);
      expect(s.single.available, 10000);
      expect(s.single.needed, 15000);
      expect(await sales.shortages([line(atta, 1000, 10000)]), isEmpty);
    });

    test('Naqad customer cannot carry udhaar; nothing is written and the '
        'bill number is not burned', () async {
      final first =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      await expectLater(
          sales.saveBill(BillInput(
              lines: [line(cheeni, 1000, 18000)], credit: true)),
          throwsA(isA<BillException>()
              .having((e) => e.error, 'error', BillError.creditNeedsCustomer)));
      expect(await db.select(db.sales).get(), hasLength(1));
      expect(await stock(cheeni), 49000);
      final next =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      int seq(String n) => int.parse(n.split('-').last);
      expect(seq(next.billNo), seq(first.billNo) + 1);
    });

    test('bill numbers increment with a stable prefix', () async {
      final a =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      final b =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      expect(a.billNo.split('-').first, b.billNo.split('-').first);
      expect(a.billNo.split('-').first, hasLength(3));
      expect(a.billNo, isNot(b.billNo));
    });

    test('validation: empty, zero qty, duplicate item, unknown item',
        () async {
      Matcher err(BillError e) =>
          throwsA(isA<BillException>().having((x) => x.error, 'e', e));
      await expectLater(sales.saveBill(const BillInput(lines: [])), err(BillError.empty));
      await expectLater(
          sales.saveBill(BillInput(lines: [line(cheeni, 0, 100)])),
          err(BillError.badQuantity));
      await expectLater(
          sales.saveBill(BillInput(
              lines: [line(cheeni, 1000, 100), line(cheeni, 1000, 100)])),
          err(BillError.duplicateItem));
      await expectLater(
          sales.saveBill(BillInput(lines: [line('nope', 1000, 100)])),
          err(BillError.unknownItem));
    });

    test('outbox carries every table touched in the same save', () async {
      await sales.saveBill(BillInput(
          lines: [line(cheeni, 1000, 18000)], customerId: ali, credit: true));
      final out = await db.select(db.outbox).get();
      final tables = out.map((o) => o.entityTable).toSet();
      expect(
          tables,
          containsAll(
              ['sales', 'sale_lines', 'stock_movements', 'customer_ledger']));
    });
  });

  group('returns', () {
    test('cash bill: stock back, refund in cash, no khata', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 2000, 18000)], customerId: ali));
      final r = await sales.createReturn(saved.saleId, {cheeni: 1000});
      expect(await stock(cheeni), 49000);
      expect((r.ledgerCredit, r.cashRefund, r.amount), (0, 18000, 18000));
      expect(await owed(ali), 0);
    });

    test('udhaar bill: return reduces khata', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 2000, 18000)], customerId: ali, credit: true));
      expect(await owed(ali), 36000);
      final r = await sales.createReturn(saved.saleId, {cheeni: 1000});
      expect((r.ledgerCredit, r.cashRefund), (18000, 0));
      expect(await owed(ali), 18000);
    });

    test('partial bill: khata first, rest cash', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 2000, 18000)],
          customerId: ali,
          credit: true,
          paidNow: 30000)); // owes 6000
      final r = await sales.createReturn(saved.saleId, {cheeni: 1000});
      expect((r.ledgerCredit, r.cashRefund), (6000, 12000));
      expect(await owed(ali), 0);
    });

    test('multiple returns, then over-return is rejected', () async {
      final saved = await sales.saveBill(
          BillInput(lines: [line(cheeni, 2000, 18000)]));
      await sales.createReturn(saved.saleId, {cheeni: 1500});
      await sales.createReturn(saved.saleId, {cheeni: 500});
      expect(await stock(cheeni), 50000);
      await expectLater(
          sales.createReturn(saved.saleId, {cheeni: 1}),
          throwsA(isA<SaleActionException>()
              .having((e) => e.error, 'e', SaleActionError.overReturn)));
    });

    test('discounted bill returns proportionally', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 2000, 18000)], discount: 3600));
      final r = await sales.createReturn(saved.saleId, {cheeni: 1000});
      expect(r.amount, 16200);
    });

    test('cancelled bill cannot be returned', () async {
      final saved =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      await sales.cancelSale(saved.saleId);
      await expectLater(sales.createReturn(saved.saleId, {cheeni: 1000}),
          throwsA(isA<SaleActionException>()));
    });
  });

  group('cancel', () {
    test('restores stock and khata exactly', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 2000, 18000), line(atta, 3000, 10000)],
          customerId: ali,
          credit: true,
          paidNow: 10000));
      await sales.cancelSale(saved.saleId);
      expect(await stock(cheeni), 50000);
      expect(await stock(atta), 10000);
      expect(await owed(ali), 0);
      final sale = await db.salesDao.saleById(saved.saleId);
      expect(sale!.status, DocStatus.cancelled);
    });

    test('after a partial return, balances still return to start', () async {
      final saved = await sales.saveBill(BillInput(
          lines: [line(cheeni, 2000, 18000)], customerId: ali, credit: true));
      await sales.createReturn(saved.saleId, {cheeni: 500});
      await sales.cancelSale(saved.saleId);
      expect(await stock(cheeni), 50000);
      expect(await owed(ali), 0);
    });

    test('double cancel is rejected', () async {
      final saved =
          await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      await sales.cancelSale(saved.saleId);
      await expectLater(
          sales.cancelSale(saved.saleId),
          throwsA(isA<SaleActionException>().having(
              (e) => e.error, 'e', SaleActionError.alreadyCancelled)));
    });
  });

  group('quick pick', () {
    test('most sold first, filled alphabetically when few sales', () async {
      await sales.saveBill(BillInput(lines: [line(atta, 1000, 10000)]));
      await sales.saveBill(BillInput(lines: [line(atta, 1000, 10000)]));
      await sales.saveBill(BillInput(lines: [line(cheeni, 1000, 18000)]));
      final picks = await db.salesDao
          .quickPickItems('shop1', now.subtract(const Duration(days: 30)));
      expect(picks.first.id, atta);
      expect(picks.map((i) => i.id), containsAll([atta, cheeni]));
    });
  });
}
