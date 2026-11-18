import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/accounts/data/accounts_repository.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';
import 'package:galla/features/khata/data/khata_repository.dart';
import 'package:galla/features/purchase/data/purchase_repository.dart';

void main() {
  late AppDatabase db;
  late AccountsRepository accounts;
  late KhataRepository khata;
  late SalesRepository sales;
  late PurchaseRepository purchases;
  late InventoryRepository inv;
  late CustomerRepository customers;
  late SupplierRepository suppliers;
  final now = DateTime(2026, 11, 16, 10);

  Future<void> boot({int openingCash = 0}) async {
    db = AppDatabase(NativeDatabase.memory());
    await ShopRepository(db).createShop(
        shopId: 'shop1',
        shopName: 'Test Store',
        phone: '+923001234567',
        openingCash: openingCash);
    accounts = AccountsRepository(db, () => 'shop1', () => now);
    khata = KhataRepository(db, () => 'shop1', () => now);
    sales = SalesRepository(db, () => 'shop1', () => now, random: Random(1));
    purchases =
        PurchaseRepository(db, () => 'shop1', () => now, random: Random(2));
    inv = InventoryRepository(db, () => 'shop1', () => now);
    customers = CustomerRepository(db, () => 'shop1', () => now);
    suppliers = SupplierRepository(db, () => 'shop1', () => now);
  }

  tearDown(() => db.close());

  PurchaseError? purchaseError(Object e) =>
      e is PurchaseException ? e.error : null;

  test('a new shop starts with exactly the cash it was given', () async {
    await boot(openingCash: 250000);
    final a = await accounts.snapshot();
    expect(a.openingCash, 250000);
    expect(a.cashInHand, 250000);
    expect(a.shopValue, 250000);
  });

  test('the 500 case: paying a supplier needs cash to exist', () async {
    await boot(); // no cash declared
    final dummy = await suppliers.create(name: 'Dummy', openingBalance: 50000);

    // We owe him 500 and have no cash, so paying 500 is refused and the
    // books do not change.
    await expectLater(
        khata.paySupplier(dummy, 50000),
        throwsA(isA<LedgerEntryException>().having(
            (e) => e.error, 'error', LedgerEntryError.insufficientCash)));
    expect(await db.khataDao.supplierBalance(dummy), 50000);
    expect((await accounts.snapshot()).cashInHand, 0);

    // With Rs 500 in the drawer the same payment goes through and the
    // cash is really gone afterwards: dena 0, cash 0.
    await accounts.setOpeningCash(50000);
    await khata.paySupplier(dummy, 50000);
    final a = await accounts.snapshot();
    expect(await db.khataDao.supplierBalance(dummy), 0);
    expect(a.cashInHand, 0);
    expect(a.supplierPaid, 50000);
  });

  test('payment error reports the cash that is available', () async {
    await boot(openingCash: 30000);
    final s = await suppliers.create(name: 'Rehman');
    await expectLater(
        khata.paySupplier(s, 30001),
        throwsA(isA<LedgerEntryException>()
            .having((e) => e.available, 'available', 30000)));
    await khata.paySupplier(s, 30000); // exactly the cash is fine
  });

  test('purchase paid now is limited by cash; unpaid part goes to dena',
      () async {
    await boot(openingCash: 10000);
    final s = await suppliers.create(name: 'Rehman');
    final cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000));

    await expectLater(
        purchases.savePurchase(PurchaseInput(
            supplierId: s,
            lines: [PurchaseLineInput(itemId: cheeni, qty: 1000, unitCost: 16500)],
            paidNow: 16500)),
        throwsA(predicate((e) =>
            purchaseError(e) == PurchaseError.insufficientCash)));
    expect(await db.select(db.purchases).get(), isEmpty);

    await purchases.savePurchase(PurchaseInput(
        supplierId: s,
        lines: [PurchaseLineInput(itemId: cheeni, qty: 1000, unitCost: 16500)],
        paidNow: 10000));
    final a = await accounts.snapshot();
    expect(a.cashInHand, 0);
    expect(a.weOwe, 6500);
  });

  test('a fully credit purchase needs no cash', () async {
    await boot();
    final s = await suppliers.create(name: 'Rehman');
    final cheeni = await inv.createItem(const ItemInput(
        name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000));
    await purchases.savePurchase(PurchaseInput(
        supplierId: s,
        lines: [PurchaseLineInput(itemId: cheeni, qty: 2000, unitCost: 16500)]));
    final a = await accounts.snapshot();
    expect(a.cashInHand, 0);
    expect(a.weOwe, 33000);
    expect(a.stockValue, 33000);
    // stock 330 owed 330: the shop is worth 0, not negative or inflated.
    expect(a.shopValue, 0);
  });

  test('cash sales and customer payments add cash; cash refunds and '
      'cancelled bills take it back', () async {
    await boot(openingCash: 100000);
    final cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000),
        openingStock: 20000);
    final ali = await customers.create(name: 'Ali', openingBalance: 40000);

    final bill = await sales.saveBill(BillInput(
        lines: [BillLineInput(itemId: cheeni, qty: 2000, unitPrice: 18000)]));
    expect((await accounts.snapshot()).cashInHand, 100000 + 36000);

    await khata.receivePayment(ali, 10000);
    final afterPay = await accounts.snapshot();
    expect(afterPay.cashInHand, 100000 + 36000 + 10000);
    expect(afterPay.customersOwe, 30000);

    await sales.cancelSale(bill.saleId);
    final afterCancel = await accounts.snapshot();
    expect(afterCancel.cashInHand, 100000 + 10000);
    expect(afterCancel.cashSales, 0);
  });

  test('udhaar bills bring no cash, only lena', () async {
    await boot(openingCash: 5000);
    final cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000),
        openingStock: 5000);
    final ali = await customers.create(name: 'Ali');
    await sales.saveBill(BillInput(
        lines: [BillLineInput(itemId: cheeni, qty: 1000, unitPrice: 18000)],
        customerId: ali,
        credit: true,
        paidNow: 3000));
    final a = await accounts.snapshot();
    expect(a.cashInHand, 5000 + 3000);
    expect(a.customersOwe, 15000);
    // stock 4kg at cost + cash + lena
    expect(a.stockValue, 4 * 16500);
    expect(a.shopValue, 8000 + 66000 + 15000);
  });

  test('changing opening cash moves cash in hand by the difference and '
      'syncs the shop row', () async {
    await boot(openingCash: 10000);
    final before = (await db.select(db.outbox).get()).length;
    await accounts.setOpeningCash(25000);
    expect((await accounts.snapshot()).cashInHand, 25000);
    final out = await db.select(db.outbox).get();
    expect(out.length, before + 1);
    expect(out.last.entityTable, 'shops');
    await expectLater(accounts.setOpeningCash(-1), throwsArgumentError);
  });

  test('stock value counts what is on the shelf at cost', () async {
    await boot();
    await inv.createItem(
        const ItemInput(
            name: 'Atta', unit: ItemUnit.piece, costPrice: 8000, salePrice: 10000),
        openingStock: 3000);
    expect((await accounts.snapshot()).stockValue, 24000);
  });
}
