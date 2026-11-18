import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';
import 'package:galla/features/khata/data/khata_repository.dart';

void main() {
  late AppDatabase db;
  late KhataRepository khata;
  late CustomerRepository customers;
  late SupplierRepository suppliers;
  late SalesRepository sales;
  late String ali;
  late String rehman;
  var now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    now = DateTime(2026, 11, 14, 10);
    db = AppDatabase(NativeDatabase.memory());
    await ShopRepository(db).createShop(
        shopId: 'shop1',
        shopName: 'Test Store',
        phone: '+923001234567',
        openingCash: 100000000);
    khata = KhataRepository(db, () => 'shop1', () => now);
    customers = CustomerRepository(db, () => 'shop1', () => now);
    suppliers = SupplierRepository(db, () => 'shop1', () => now);
    sales = SalesRepository(db, () => 'shop1', () => now);
    ali = await customers.create(name: 'Ali', openingBalance: 100000);
    rehman = await suppliers.create(name: 'Rehman', openingBalance: 50000);
  });
  tearDown(() => db.close());

  Future<int> owed() => db.khataDao.customerBalance(ali);
  Future<int> dena() => db.khataDao.supplierBalance(rehman);

  group('customer payments', () {
    test('payment reduces the balance and writes payment_received', () async {
      await khata.receivePayment(ali, 30000, note: 'Nakad');
      expect(await owed(), 70000);
      final rows = await db.khataDao.customerLedgerRows(ali);
      final p = rows.firstWhere((r) => r.type == CustomerLedgerType.paymentReceived);
      expect(p.amount, -30000);
      expect(p.note, 'Nakad');
    });

    test('paying more than owed makes an advance', () async {
      await khata.receivePayment(ali, 130000);
      expect(await owed(), -30000);
      final h = await khata.customerHistory(ali);
      expect(h.balance, -30000);
    });

    test('manual udhaar adds to the balance', () async {
      await khata.addUdhaar(ali, 2500);
      expect(await owed(), 102500);
      final rows = await db.khataDao.customerLedgerRows(ali);
      expect(rows.last.type, CustomerLedgerType.manualUdhaar);
    });

    test('amount must be positive; unknown and Naqad customers rejected',
        () async {
      Matcher err(LedgerEntryError e) =>
          throwsA(isA<LedgerEntryException>().having((x) => x.error, 'e', e));
      await expectLater(khata.receivePayment(ali, 0), err(LedgerEntryError.badAmount));
      await expectLater(khata.addUdhaar(ali, -5), err(LedgerEntryError.badAmount));
      await expectLater(
          khata.receivePayment('nope', 100), err(LedgerEntryError.unknownParty));
      await expectLater(khata.addUdhaar(naqadCustomerId('shop1'), 100),
          err(LedgerEntryError.systemCustomer));
      expect(await owed(), 100000);
    });

    test('picked date is kept, with the current time of day', () async {
      await khata.receivePayment(ali, 1000, date: DateTime(2026, 11, 2));
      final p = (await db.khataDao.customerLedgerRows(ali))
          .firstWhere((r) => r.type == CustomerLedgerType.paymentReceived);
      expect(p.date.year, 2026);
      expect(p.date.month, 11);
      expect(p.date.day, 2);
      expect(p.date.hour, 10);
    });

    test('rows go to the outbox in the same write', () async {
      final before = (await db.select(db.outbox).get()).length;
      await khata.receivePayment(ali, 1000);
      final out = await db.select(db.outbox).get();
      expect(out.length, before + 1);
      expect(out.last.entityTable, 'customer_ledger');
    });
  });

  group('supplier payments', () {
    test('payment reduces dena; overpay is an advance', () async {
      await khata.paySupplier(rehman, 20000);
      expect(await dena(), 30000);
      await khata.paySupplier(rehman, 40000);
      expect(await dena(), -10000);
    });

    test('rejects zero and unknown supplier', () async {
      await expectLater(khata.paySupplier(rehman, 0),
          throwsA(isA<LedgerEntryException>()));
      await expectLater(khata.paySupplier('nope', 100),
          throwsA(isA<LedgerEntryException>()));
    });
  });

  group('history', () {
    test('bills show number and items; balance equals SUM of ledger',
        () async {
      final cheeni = await InventoryRepository(db, () => 'shop1', () => now)
          .createItem(
              const ItemInput(
                  name: 'Cheeni', unit: ItemUnit.kg, salePrice: 18000),
              openingStock: 10000);
      now = DateTime(2026, 11, 14, 11);
      final saved = await sales.saveBill(BillInput(
          lines: [BillLineInput(itemId: cheeni, qty: 1000, unitPrice: 18000)],
          customerId: ali,
          credit: true));
      now = DateTime(2026, 11, 14, 12);
      await khata.receivePayment(ali, 50000);

      final h = await khata.customerHistory(ali);
      expect(h.balance, await owed());
      expect(h.balance, 100000 + 18000 - 50000);
      final bill = h.entries
          .firstWhere((e) => e.type == CustomerLedgerType.saleCredit);
      expect(bill.docNo, saved.billNo);
      expect(bill.itemsText, 'Cheeni');
      expect(bill.refId, saved.saleId);
      expect(h.entries.first.type, CustomerLedgerType.paymentReceived);
      expect(h.entries.first.balanceAfter, h.balance);
    });

    test('cancelling a bill shows up in history and balances', () async {
      final cheeni = await InventoryRepository(db, () => 'shop1', () => now)
          .createItem(
              const ItemInput(name: 'Cheeni', unit: ItemUnit.kg),
              openingStock: 10000);
      final saved = await sales.saveBill(BillInput(
          lines: [BillLineInput(itemId: cheeni, qty: 1000, unitPrice: 18000)],
          customerId: ali,
          credit: true));
      await sales.cancelSale(saved.saleId);
      final h = await khata.customerHistory(ali);
      expect(h.balance, 100000);
      expect(h.entries.any((e) => e.docNo == saved.billNo && e.type == CustomerLedgerType.adjustment),
          isTrue);
    });

    test('supplier history = SUM of supplier ledger', () async {
      await khata.paySupplier(rehman, 15000);
      final h = await khata.supplierHistory(rehman);
      expect(h.balance, 35000);
      expect(h.balance, await dena());
    });
  });
}
