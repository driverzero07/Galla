import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/db/daos/device_state_dao.dart';
import 'package:galla/core/sync/sync_remote.dart';
import 'package:galla/core/sync/sync_service.dart';
import 'package:galla/features/auth/data/restore_service.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';

import 'fake_remote.dart';

class Phone {
  Phone(this.name, this.remote, {required this.prefix});
  final String name;
  final FakeRemote remote;
  final String prefix;
  late final AppDatabase db = AppDatabase(NativeDatabase.memory());
  DateTime clock = DateTime(2026, 11, 14, 10);
  late final SyncService sync =
      SyncService(db, remote, () => 'shop1', now: () => clock);
  late final SalesRepository sales =
      SalesRepository(db, () => 'shop1', () => clock, random: Random(3));
  late final InventoryRepository inv =
      InventoryRepository(db, () => 'shop1', () => clock);
  late final CustomerRepository customers =
      CustomerRepository(db, () => 'shop1', () => clock);

  Future<void> init({bool createShop = false}) async {
    await db.deviceStateDao.set(DeviceStateDao.prefixKey, prefix);
    if (createShop) {
      await ShopRepository(db).createShop(
          shopId: 'shop1',
          shopName: 'Ali General Store',
          phone: '+923001234567',
          now: clock);
    }
  }

  Future<int> stockOf(String id) => db.inventoryDao.stockOf(id);
  Future<int> owed(String id) => db.khataDao.customerBalance(id);
  Future<void> close() => db.close();
}

void main() {
  late FakeRemote remote;

  setUp(() => remote = FakeRemote());

  group('backoff', () {
    test('5 s doubling, capped at 15 minutes', () {
      expect(syncBackoff(0), Duration.zero);
      expect(syncBackoff(1), const Duration(seconds: 5));
      expect(syncBackoff(2), const Duration(seconds: 10));
      expect(syncBackoff(3), const Duration(seconds: 20));
      expect(syncBackoff(20), const Duration(minutes: 15));
    });
  });

  group('push', () {
    test('sends the outbox in batches of 50 and empties it', () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      for (var i = 0; i < 60; i++) {
        await a.customers.create(name: 'Customer $i', openingBalance: 1000 + i);
      }
      // shop, settings, naqad + 60 customers + 60 opening ledger rows
      expect(await a.db.outboxDao.pendingCount(), 123);

      expect(await a.sync.syncNow(reason: 'test'), isTrue);

      expect(await a.db.outboxDao.pendingCount(), 0);
      expect(remote.upserts.every((u) => u.rows <= 50), isTrue);
      expect(remote.count('customers'), 61);
      expect(remote.count('customer_ledger'), 60);
      expect(remote.count('shops'), 1);
      expect(a.sync.state.failure, isNull);
      expect(await a.sync.lastSyncAt(), isNotNull);
      await a.close();
    });

    test('a failed request keeps the unconfirmed rows and backs off',
        () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      await a.customers.create(name: 'Akram', openingBalance: 5000);
      final before = await a.db.outboxDao.pendingCount();
      remote.failUpsertAt = 1; // first table goes through, the second fails

      expect(await a.sync.syncNow(reason: 'test'), isFalse);
      expect(a.sync.state.failure, SyncFailure.offline);
      final left = await a.db.outboxDao.pendingCount();
      expect(left, greaterThan(0));
      expect(left, lessThan(before));
      final stuck = await a.db.outboxDao.nextBatch();
      expect(stuck.first.attempts, 1);

      // Automatic retries wait; the manual button does not.
      expect(await a.sync.syncNow(reason: 'timer'), isFalse);
      a.clock = a.clock.add(const Duration(seconds: 6));
      expect(await a.sync.syncNow(reason: 'timer'), isTrue);
      expect(await a.db.outboxDao.pendingCount(), 0);
      await a.close();
    });

    test('forced sync ignores the wait', () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      remote.failUpsertAt = 0;
      expect(await a.sync.syncNow(reason: 'test'), isFalse);
      expect(await a.sync.syncNow(reason: 'manual', force: true), isTrue);
      await a.close();
    });

    test('pushing the same rows again changes nothing (idempotent)', () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      await a.customers.create(name: 'Akram', openingBalance: 5000);
      await a.sync.syncNow(reason: 'test');
      final counts = {for (final t in remote.tables.keys) t: remote.count(t)};

      // Replay everything: queue the same rows once more.
      for (final c in await a.db.select(a.db.customers).get()) {
        await a.db.outboxDao.enqueue(
            table: 'customers',
            rowId: c.id,
            op: OutboxOp.update,
            payload: _json(c.toJson()),
            now: a.clock);
      }
      a.clock = a.clock.add(const Duration(minutes: 1));
      await a.sync.syncNow(reason: 'test', force: true);
      expect({for (final t in remote.tables.keys) t: remote.count(t)}, counts);
      await a.close();
    });

    test('not signed in: nothing is sent and the phone keeps its queue',
        () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      remote.ready = false;
      expect(await a.sync.syncNow(reason: 'test'), isFalse);
      expect(a.sync.state.failure, SyncFailure.notReady);
      expect(await a.db.outboxDao.pendingCount(), greaterThan(0));
      expect(remote.upserts, isEmpty);
      await a.close();
    });
  });

  group('pull and restore', () {
    Future<Phone> shopWithData() async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      final cheeni = await a.inv.createItem(
          const ItemInput(
              name: 'Cheeni',
              unit: ItemUnit.kg,
              costPrice: 16500,
              salePrice: 18000),
          openingStock: 50000);
      final ali = await a.customers.create(name: 'Ali', openingBalance: 25000);
      await a.sales.saveBill(BillInput(
          lines: [BillLineInput(itemId: cheeni, qty: 2000, unitPrice: 18000)],
          customerId: ali,
          credit: true));
      await a.sync.syncNow(reason: 'test');
      return a;
    }

    test('a new phone restores everything and the numbers match', () async {
      final a = await shopWithData();
      final b = Phone('B', remote, prefix: 'BBB');
      await b.init();

      final found = await RestoreService(b.db, remote).restoreIfExists('shop1');
      expect(found, isTrue);

      final aItems = await a.db.select(a.db.items).get();
      final bItems = await b.db.select(b.db.items).get();
      expect(bItems.map((i) => i.id).toSet(), aItems.map((i) => i.id).toSet());
      for (final i in aItems) {
        expect(await b.stockOf(i.id), await a.stockOf(i.id));
      }
      final aCust = await a.db.select(a.db.customers).get();
      for (final c in aCust) {
        expect(await b.owed(c.id), await a.owed(c.id));
      }
      expect((await b.db.select(b.db.sales).get()).length, 1);
      expect((await b.db.select(b.db.shops).get()).single.name,
          'Ali General Store');
      expect(await b.db.select(b.db.appSettings).get(), hasLength(1));
      // Restoring queues nothing to push back.
      expect(await b.db.outboxDao.pendingCount(), 0);
      await a.close();
      await b.close();
    });

    test('no shop on the server means a normal first-time setup', () async {
      final b = Phone('B', remote, prefix: 'BBB');
      await b.init();
      expect(await RestoreService(b.db, remote).restoreIfExists('shop1'),
          isFalse);
      await b.close();
    });

    test('a half finished restore resumes from the saved cursors', () async {
      final a = await shopWithData();
      final b = Phone('B', remote, prefix: 'BBB');
      await b.init();
      await b.sync.pullChanges('shop1');
      final first = await b.db.select(b.db.sales).get();
      await b.sync.pullChanges('shop1'); // second pass: same data, no harm
      expect(await b.db.select(b.db.sales).get(), hasLength(first.length));
      await a.close();
      await b.close();
    });

    test('an unsent local change is not overwritten by a pull', () async {
      final a = await shopWithData();
      final b = Phone('B', remote, prefix: 'BBB');
      await b.init();
      await b.sync.pullChanges('shop1');
      final ali =
          (await b.db.select(b.db.customers).get()).firstWhere((c) => c.name == 'Ali');

      // A renames Ali and syncs; B renames Ali offline.
      a.clock = a.clock.add(const Duration(minutes: 1));
      await a.db.update(a.db.customers).replace(
          (await a.db.khataDao.customerById(ali.id))!
              .copyWith(name: 'Ali Server', updatedAt: a.clock));
      final aRow = (await a.db.khataDao.customerById(ali.id))!;
      await a.db.outboxDao.enqueue(
          table: 'customers',
          rowId: ali.id,
          op: OutboxOp.update,
          payload: _json(aRow.toJson()),
          now: a.clock);
      await a.sync.syncNow(reason: 'test', force: true);

      await b.db.update(b.db.customers).replace(
          ali.copyWith(name: 'Ali Local', updatedAt: b.clock));
      final bRow = (await b.db.khataDao.customerById(ali.id))!;
      await b.db.outboxDao.enqueue(
          table: 'customers',
          rowId: ali.id,
          op: OutboxOp.update,
          payload: _json(bRow.toJson()),
          now: b.clock);
      await b.sync.pullChanges('shop1');
      expect((await b.db.khataDao.customerById(ali.id))!.name, 'Ali Local');

      // After B pushes, the latest arrival wins everywhere.
      await b.sync.syncNow(reason: 'test', force: true);
      await a.sync.syncNow(reason: 'test', force: true);
      expect((await a.db.khataDao.customerById(ali.id))!.name, 'Ali Local');
      await a.close();
      await b.close();
    });
  });

  group('two phones, one shop', () {
    test('offline bills on both phones sync with matching totals and no clash',
        () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      final cheeni = await a.inv.createItem(
          const ItemInput(
              name: 'Cheeni',
              unit: ItemUnit.kg,
              costPrice: 16500,
              salePrice: 18000),
          openingStock: 100000);
      final ali = await a.customers.create(name: 'Ali');
      await a.sync.syncNow(reason: 'setup');

      final b = Phone('B', remote, prefix: 'BBB');
      await b.init();
      await RestoreService(b.db, remote).restoreIfExists('shop1');

      // Both phones are offline now: three bills each, some on udhaar.
      for (var i = 0; i < 3; i++) {
        await a.sales.saveBill(BillInput(
            lines: [BillLineInput(itemId: cheeni, qty: 1000, unitPrice: 18000)]));
        await b.sales.saveBill(BillInput(
            lines: [BillLineInput(itemId: cheeni, qty: 2000, unitPrice: 18000)],
            customerId: ali,
            credit: true));
      }

      // Back online: A, B, then A again to receive B's bills.
      expect(await a.sync.syncNow(reason: 'online', force: true), isTrue);
      expect(await b.sync.syncNow(reason: 'online', force: true), isTrue);
      expect(await a.sync.syncNow(reason: 'online', force: true), isTrue);

      final aSales = await a.db.select(a.db.sales).get();
      final bSales = await b.db.select(b.db.sales).get();
      expect(aSales, hasLength(6));
      expect(bSales, hasLength(6));
      expect(aSales.map((s) => s.billNo).toSet(), hasLength(6),
          reason: 'bill numbers are unique');
      expect(aSales.map((s) => s.billNo).toSet(),
          bSales.map((s) => s.billNo).toSet());
      expect(aSales.where((s) => s.billNo.startsWith('AAA-')), hasLength(3));
      expect(aSales.where((s) => s.billNo.startsWith('BBB-')), hasLength(3));
      expect(remote.count('sales'), 6);

      final total = (List<Sale> l) => l.fold<int>(0, (s, e) => s + e.total);
      expect(total(aSales), total(bSales));
      expect(total(aSales), 3 * 18000 + 3 * 36000);

      // Stock (derived from movements) and khata (derived from the ledger)
      // agree on both phones and with the arithmetic.
      expect(await a.stockOf(cheeni), 100000 - 3000 - 6000);
      expect(await b.stockOf(cheeni), await a.stockOf(cheeni));
      expect(await a.owed(ali), 3 * 36000);
      expect(await b.owed(ali), await a.owed(ali));
      await a.close();
      await b.close();
    });
  });

  group('photos', () {
    test('uploaded in the background; row keeps path and URL', () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      final dir = await Directory.systemTemp.createTemp('galla_photo');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cheeni.jpg')..writeAsBytesSync([1, 2, 3]);
      final id = await a.inv.createItem(ItemInput(
          name: 'Cheeni',
          unit: ItemUnit.kg,
          costPrice: 100,
          salePrice: 200,
          photoPath: file.path));

      await a.sync.syncNow(reason: 'test');

      final item = (await a.db.inventoryDao.itemById(id))!;
      expect(item.photoPath, file.path);
      expect(item.photoUrl, startsWith('https://fake.example/shop1/'));
      expect(remote.uploaded, [file.path]);
      expect(await a.db.outboxDao.pendingCount(), 0);
      final serverRow = remote.tables['items']![id]!;
      expect(serverRow['photo_url'], item.photoUrl);
      expect(serverRow.containsKey('photo_path'), isFalse);

      // Another phone gets the URL but not this phone's file path.
      final b = Phone('B', remote, prefix: 'BBB');
      await b.init();
      await b.sync.pullChanges('shop1');
      final onB = (await b.db.inventoryDao.itemById(id))!;
      expect(onB.photoPath, isNull);
      expect(onB.photoUrl, item.photoUrl);
      await a.close();
      await b.close();
    });

    test('a missing photo file is skipped, not fatal', () async {
      final a = Phone('A', remote, prefix: 'AAA');
      await a.init(createShop: true);
      await a.inv.createItem(const ItemInput(
          name: 'X',
          unit: ItemUnit.kg,
          costPrice: 1,
          salePrice: 2,
          photoPath: '/no/such/file.jpg'));
      expect(await a.sync.syncNow(reason: 'test'), isTrue);
      expect(remote.uploaded, isEmpty);
      await a.close();
    });
  });
}

String _json(Map<String, dynamic> m) => jsonEncode(m);
