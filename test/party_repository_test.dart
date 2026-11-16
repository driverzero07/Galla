import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';

void main() {
  late AppDatabase db;
  late CustomerRepository customers;
  late SupplierRepository suppliers;
  final now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    customers = CustomerRepository(db, () => 'shop1', () => now);
    suppliers = SupplierRepository(db, () => 'shop1', () => now);
    await ShopRepository(db).createShop(
      shopId: 'shop1',
      shopName: 'Ali General Store',
      phone: '+923001234567',
      now: now,
    );
    // Clear the setup rows so tests see only their own outbox entries.
    final setup = await db.outboxDao.nextBatch();
    await db.outboxDao.markDone(setup.map((e) => e.id));
  });
  tearDown(() => db.close());

  group('customers', () {
    test('opening balance becomes an opening ledger row', () async {
      final id = await customers.create(
          name: 'Akram Sahib', phone: '0300 1234567', openingBalance: 340000);
      final ledger = await db.select(db.customerLedger).get();
      expect(ledger, hasLength(1));
      expect(ledger.single.type, CustomerLedgerType.opening);
      expect(ledger.single.amount, 340000);
      expect(await db.khataDao.customerBalance(id), 340000);
      final tables =
          (await db.outboxDao.nextBatch()).map((e) => e.entityTable).toList();
      expect(tables, ['customers', 'customer_ledger']);
    });

    test('no opening balance means no ledger row', () async {
      await customers.create(name: 'Bilal Bhai');
      expect(await db.select(db.customerLedger).get(), isEmpty);
    });

    test('validation', () async {
      await expectLater(customers.create(name: '  '),
          throwsA(isA<PartyValidationException>()));
      await expectLater(customers.create(name: 'A', openingBalance: -1),
          throwsA(isA<PartyValidationException>()));
    });

    test('phone is normalised, blank becomes null', () async {
      final a = await customers.create(name: 'A', phone: '0300 1234567');
      final b = await customers.create(name: 'B', phone: '   ');
      final c = await customers.create(name: 'C', phone: '042-111');
      expect((await db.khataDao.customerById(a))?.phone, '+923001234567');
      expect((await db.khataDao.customerById(b))?.phone, isNull);
      expect((await db.khataDao.customerById(c))?.phone, '042-111');
    });

    test('list hides the system Naqad customer and shows balances', () async {
      final id = await customers.create(
          name: 'Akram Sahib', openingBalance: 340000);
      final rows = await customers.watch().first;
      expect(rows.map((r) => r.name), ['Akram Sahib']);
      expect(rows.single.balance, 340000);

      await db.into(db.customerLedger).insert(CustomerLedgerCompanion.insert(
            id: 'l2',
            shopId: 'shop1',
            customerId: id,
            type: CustomerLedgerType.paymentReceived,
            amount: -200000,
            date: now,
            createdAt: now,
            updatedAt: now,
          ));
      expect((await customers.watch().first).single.balance, 140000);
    });

    test('Naqad customer cannot be edited or hidden', () async {
      final naqad = naqadCustomerId('shop1');
      await expectLater(customers.update(naqad, name: 'Hacked'),
          throwsA(isA<SystemCustomerException>()));
      await expectLater(customers.setArchived(naqad, true),
          throwsA(isA<SystemCustomerException>()));
      expect((await db.khataDao.customerById(naqad))?.isArchived, isFalse);
    });

    test('edit and hide / unhide', () async {
      final id = await customers.create(name: 'Akram');
      await customers.update(id, name: 'Akram Sahib', phone: '0301 5555555');
      expect((await customers.info(id))?.name, 'Akram Sahib');

      await customers.setArchived(id, true);
      expect(await customers.watch().first, isEmpty);
      expect((await customers.watch(includeArchived: true).first).single.isArchived,
          isTrue);
      await customers.setArchived(id, false);
      expect(await customers.watch().first, hasLength(1));
    });

    test('search matches name or phone, and % is not a wildcard', () async {
      await customers.create(name: 'Akram Sahib', phone: '0300 1234567');
      await customers.create(name: 'Bilal Bhai', phone: '0321 7654321');
      expect((await customers.watch(query: 'bil').first).single.name,
          'Bilal Bhai');
      expect((await customers.watch(query: '7654').first).single.name,
          'Bilal Bhai');
      expect(await customers.watch(query: '%').first, isEmpty);
      expect(await customers.watch(query: '_').first, isEmpty);
    });
  });

  group('suppliers', () {
    test('opening balance is what we owe the supplier', () async {
      final id = await suppliers.create(
          name: 'Rehman Traders', openingBalance: 1175000);
      final ledger = await db.select(db.supplierLedger).get();
      expect(ledger.single.type, SupplierLedgerType.opening);
      expect(await db.khataDao.supplierBalance(id), 1175000);
      expect((await suppliers.watch().first).single.balance, 1175000);
    });

    test('edit, hide, unhide', () async {
      final id = await suppliers.create(name: 'Rehman');
      await suppliers.update(id, name: 'Rehman Traders');
      await suppliers.setArchived(id, true);
      expect(await suppliers.watch().first, isEmpty);
      expect(await suppliers.watch(includeArchived: true).first, hasLength(1));
      await suppliers.setArchived(id, false);
      expect((await suppliers.watch().first).single.name, 'Rehman Traders');
    });

    test('customers and suppliers are separate lists', () async {
      await customers.create(name: 'Akram');
      await suppliers.create(name: 'Rehman');
      expect((await customers.watch().first).map((r) => r.name), ['Akram']);
      expect((await suppliers.watch().first).map((r) => r.name), ['Rehman']);
    });
  });
}
