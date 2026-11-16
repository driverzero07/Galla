import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/migration/data/import_repository.dart';

void main() {
  late AppDatabase db;
  late ImportRepository repo;
  late CustomerRepository customers;
  final now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ImportRepository(db, () => 'shop1', () => now);
    customers = CustomerRepository(db, () => 'shop1', () => now);
    await ShopRepository(db).createShop(
      shopId: 'shop1',
      shopName: 'Ali General Store',
      phone: '+923001234567',
      now: now,
    );
    final setup = await db.outboxDao.nextBatch();
    await db.outboxDao.markDone(setup.map((e) => e.id));
  });
  tearDown(() => db.close());

  Future<List<Customer>> allCustomers() => db.select(db.customers).get();

  group('commitParties', () {
    test('creates customers with opening balances and one batch', () async {
      final res = await repo.commitParties(
        kind: ImportKind.customers,
        rows: const [
          ImportPartyInput(name: 'Akram', paisa: 340000),
          ImportPartyInput(name: 'Bilal', phone: '+923001234567', paisa: 0),
        ],
        method: ImportMethod.quick,
      );
      expect(res.count, 2);
      expect(res.totalAmount, 340000);
      final cs = await allCustomers();
      expect(cs, hasLength(2));
      final akram = cs.firstWhere((c) => c.name == 'Akram');
      expect(await db.khataDao.customerBalance(akram.id), 340000);
      final ledger = await db.select(db.customerLedger).get();
      expect(ledger, hasLength(1)); // zero balance writes no row
      expect(ledger.single.type, CustomerLedgerType.opening);
      expect(ledger.single.refId, res.batchId);
      final batches = await db.select(db.importBatches).get();
      expect(batches.single.rowCount, 2);
      expect(batches.single.method, ImportMethod.quick);
      final tables = (await db.outboxDao.nextBatch())
          .map((e) => e.entityTable)
          .toSet();
      expect(tables, containsAll(
          ['customers', 'customer_ledger', 'import_batches']));
    });

    test('suppliers', () async {
      final res = await repo.commitParties(
        kind: ImportKind.suppliers,
        rows: const [ImportPartyInput(name: 'Sheikh Traders', paisa: 500000)],
      );
      final s = (await db.select(db.suppliers).get()).single;
      expect(await db.khataDao.supplierBalance(s.id), 500000);
      expect(res.totalAmount, 500000);
    });

    test('empty or bad rows are refused and nothing is written', () async {
      await expectLater(
          repo.commitParties(kind: ImportKind.customers, rows: const []),
          throwsA(isA<ImportException>()));
      await expectLater(
          repo.commitParties(kind: ImportKind.customers, rows: const [
            ImportPartyInput(name: 'Good', paisa: 100),
            ImportPartyInput(name: ' ', paisa: 100),
          ]),
          throwsA(isA<ImportException>()));
      expect(await allCustomers(), isEmpty);
      expect(await db.select(db.importBatches).get(), isEmpty);
    });

    test('existingPartyKeys sees saved customers', () async {
      await customers.create(name: 'Akram');
      final keys = await repo.existingPartyKeys(ImportKind.customers);
      expect(keys, contains('akram|'));
    });
  });

  group('commitItems', () {
    test('creates items with opening stock', () async {
      final res = await repo.commitItems(rows: const [
        ImportItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, cost: 15000, price: 17000, stock: 25000, barcode: '111'),
        ImportItemInput(name: 'Chai', price: 500),
      ]);
      expect(res.count, 2);
      final items = await db.select(db.items).get();
      final cheeni = items.firstWhere((i) => i.name == 'Cheeni');
      expect(await db.inventoryDao.stockOf(cheeni.id), 25000);
      final moves = await db.select(db.stockMovements).get();
      expect(moves, hasLength(1));
      expect(moves.single.reason, StockReason.opening);
      expect(moves.single.refId, res.batchId);
    });

    test('a taken barcode rolls the whole import back', () async {
      await repo.commitItems(rows: const [
        ImportItemInput(name: 'First', barcode: '999'),
      ]);
      await expectLater(
          repo.commitItems(rows: const [
            ImportItemInput(name: 'New one', barcode: '555'),
            ImportItemInput(name: 'Clash', barcode: '999'),
          ]),
          throwsA(isA<ImportException>()));
      final names = (await db.select(db.items).get()).map((i) => i.name);
      expect(names, ['First']);
      expect(await db.select(db.importBatches).get(), hasLength(1));
    });
  });

  group('undo', () {
    test('customers: balance returns to zero, rows archived, not deleted',
        () async {
      final res = await repo.commitParties(
        kind: ImportKind.customers,
        rows: const [ImportPartyInput(name: 'Akram', paisa: 340000)],
      );
      expect(await repo.blockedCount(res.batchId), 0);
      await repo.undoBatch(res.batchId);
      final c = (await allCustomers()).single;
      expect(c.isArchived, isTrue);
      expect(await db.khataDao.customerBalance(c.id), 0);
      expect(await db.select(db.customerLedger).get(), hasLength(2));
      final b = (await db.select(db.importBatches).get()).single;
      expect(b.undoneAt, isNotNull);
    });

    test('items: stock reversed and items archived', () async {
      final res = await repo.commitItems(rows: const [
        ImportItemInput(name: 'Cheeni', stock: 10000),
      ]);
      await repo.undoBatch(res.batchId);
      final item = (await db.select(db.items).get()).single;
      expect(item.isArchived, isTrue);
      expect(await db.inventoryDao.stockOf(item.id), 0);
    });

    test('blocked once a customer has later activity', () async {
      final res = await repo.commitParties(
        kind: ImportKind.customers,
        rows: const [
          ImportPartyInput(name: 'Akram', paisa: 340000),
          ImportPartyInput(name: 'Bilal', paisa: 100),
        ],
      );
      final akram =
          (await allCustomers()).firstWhere((c) => c.name == 'Akram');
      await db.into(db.customerLedger).insert(CustomerLedgerCompanion.insert(
            id: 'pay1',
            shopId: 'shop1',
            customerId: akram.id,
            type: CustomerLedgerType.paymentReceived,
            amount: -100000,
            date: now,
            createdAt: now,
            updatedAt: now,
          ));
      expect(await repo.blockedCount(res.batchId), 1);
      await expectLater(
        repo.undoBatch(res.batchId),
        throwsA(isA<ImportException>()
            .having((e) => e.error, 'error', ImportError.undoBlocked)
            .having((e) => e.count, 'count', 1)),
      );
      // Nothing changed.
      expect((await allCustomers()).every((c) => !c.isArchived), isTrue);
      expect(await db.khataDao.customerBalance(akram.id), 240000);
    });

    test('cannot undo twice, unknown batch', () async {
      final res = await repo.commitParties(
        kind: ImportKind.customers,
        rows: const [ImportPartyInput(name: 'Akram', paisa: 100)],
      );
      await repo.undoBatch(res.batchId);
      await expectLater(
          repo.undoBatch(res.batchId),
          throwsA(isA<ImportException>()
              .having((e) => e.error, 'error', ImportError.alreadyUndone)));
      await expectLater(
          repo.undoBatch('nope'),
          throwsA(isA<ImportException>()
              .having((e) => e.error, 'error', ImportError.notFound)));
    });
  });
}
