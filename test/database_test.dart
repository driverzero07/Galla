import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/sync/outbox_writer.dart';
import 'package:galla/features/auth/data/shop_repository.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 11, 13, 9);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Set<String>> names(String type) async {
    final rows = await db
        .customSelect('SELECT name FROM sqlite_master WHERE type = ?1',
            variables: [Variable.withString(type)])
        .get();
    return {for (final r in rows) r.read<String>('name')};
  }

  Future<void> addItem(String id, String name, {String? barcode}) {
    return db.into(db.items).insert(ItemsCompanion.insert(
          id: id,
          shopId: 'shop1',
          name: name,
          barcode: Value(barcode),
          createdAt: now,
          updatedAt: now,
        ));
  }

  group('schema and migration', () {
    test('creates every table from the data model', () async {
      final tables = await names('table');
      expect(
        tables,
        containsAll(<String>[
          'shops',
          'items',
          'stock_movements',
          'customers',
          'customer_ledger',
          'suppliers',
          'supplier_ledger',
          'sales',
          'sale_lines',
          'sale_returns',
          'sale_return_lines',
          'purchases',
          'purchase_lines',
          'outbox',
          'settings',
          'items_fts',
        ]),
      );
    });

    test('creates the required indexes', () async {
      final indexes = await names('index');
      expect(
        indexes,
        containsAll(<String>[
          'idx_items_shop_barcode',
          'idx_stock_movements_item',
          'idx_customer_ledger_customer',
        ]),
      );
    });

    test('schema version is recorded', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), AppDatabase.currentSchemaVersion);
    });
  });

  group('first run', () {
    test('createShop seeds shop, settings and the Naqad customer, and queues '
        'them for sync', () async {
      final repo = ShopRepository(db);
      await repo.createShop(
        shopId: 'shop1',
        shopName: 'Ali General Store',
        phone: '+923001234567',
        now: now,
      );

      final shop = await db.shopDao.shopById('shop1');
      expect(shop?.name, 'Ali General Store');

      final naqad = await (db.select(db.customers)
            ..where((c) => c.id.equals(naqadCustomerId('shop1'))))
          .getSingle();
      expect(naqad.name, naqadCustomerName);
      expect(naqad.isArchived, isFalse);

      final settings = await db.shopDao.settingsFor('shop1');
      expect(settings?.pinLockMinutes, 5);

      final queued = await db.outboxDao.nextBatch();
      expect(queued.map((e) => e.entityTable),
          ['shops', 'customers', 'settings']);
    });

    test('Naqad id is deterministic per shop', () {
      expect(naqadCustomerId('a'), naqadCustomerId('a'));
      expect(naqadCustomerId('a'), isNot(naqadCustomerId('b')));
    });
  });

  group('writeWithOutbox', () {
    test('row and outbox entry are written together', () async {
      await writeWithOutbox(db, (outbox) async {
        await addItem('i1', 'Cheeni');
        outbox.record(table: 'items', rowId: 'i1', payload: {'id': 'i1'});
      }, now: () => now);

      expect(await db.select(db.items).get(), hasLength(1));
      expect(await db.outboxDao.pendingCount(), 1);
    });

    test('a failure rolls back BOTH the row and the outbox entry', () async {
      await expectLater(
        writeWithOutbox(db, (outbox) async {
          await addItem('i1', 'Cheeni');
          outbox.record(table: 'items', rowId: 'i1', payload: {'id': 'i1'});
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(await db.select(db.items).get(), isEmpty);
      expect(await db.outboxDao.pendingCount(), 0);
    });

    test('outbox is returned oldest first', () async {
      await writeWithOutbox(db, (outbox) async {
        outbox.record(table: 'items', rowId: 'a', payload: {});
        outbox.record(table: 'items', rowId: 'b', payload: {});
      });
      final batch = await db.outboxDao.nextBatch();
      expect(batch.map((e) => e.rowId), ['a', 'b']);
    });
  });

  group('items', () {
    test('barcode is unique per shop; items without a barcode never clash',
        () async {
      await addItem('i1', 'Cheeni', barcode: '123');
      await expectLater(addItem('i2', 'Chawal', barcode: '123'), throwsA(anything));
      await addItem('i3', 'Atta');
      await addItem('i4', 'Daal');
      expect(await db.select(db.items).get(), hasLength(3));
    });

    test('full-text name search finds prefixes and follows renames', () async {
      await addItem('i1', 'Cheeni');
      await addItem('i2', 'Chai patti');
      await addItem('i3', 'Atta');

      expect(await db.inventoryDao.searchItemIds('shop1', 'che'), ['i1']);
      expect(
        (await db.inventoryDao.searchItemIds('shop1', 'ch')).toSet(),
        {'i1', 'i2'},
      );

      await (db.update(db.items)..where((t) => t.id.equals('i3')))
          .write(const ItemsCompanion(name: Value('Chawal')));
      expect(await db.inventoryDao.searchItemIds('shop1', 'chaw'), ['i3']);
      expect(await db.inventoryDao.searchItemIds('shop1', 'atta'), isEmpty);
    });

    test('search ignores punctuation and empty input', () async {
      await addItem('i1', 'Cheeni');
      expect(await db.inventoryDao.searchItemIds('shop1', '"; DROP'), isEmpty);
      expect(await db.inventoryDao.searchItemIds('shop1', '   '), isEmpty);
    });
  });

  group('derived balances', () {
    test('stock is the SUM of movements', () async {
      Future<void> move(String id, int qty) =>
          db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
                id: id,
                shopId: 'shop1',
                itemId: 'i1',
                qty: qty,
                reason: 'opening',
                createdAt: now,
                updatedAt: now,
              ));
      await move('m1', 50000);
      await move('m2', -2500);
      expect(await db.inventoryDao.stockOf('i1'), 47500);
      expect(await db.inventoryDao.stockOf('nothing'), 0);
    });

    test('customer balance is the SUM of ledger rows (negative = advance)',
        () async {
      Future<void> entry(String id, int amount) =>
          db.into(db.customerLedger).insert(CustomerLedgerCompanion.insert(
                id: id,
                shopId: 'shop1',
                customerId: 'c1',
                type: 'adjustment',
                amount: amount,
                date: now,
                createdAt: now,
                updatedAt: now,
              ));
      await entry('l1', 340000);
      await entry('l2', -200000);
      expect(await db.khataDao.customerBalance('c1'), 140000);
      await entry('l3', -300000);
      expect(await db.khataDao.customerBalance('c1'), -160000);
    });
  });
}
