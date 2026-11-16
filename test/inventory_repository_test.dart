import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/db/daos/inventory_dao.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository repo;
  final now = DateTime(2026, 11, 14, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryRepository(db, () => 'shop1', () => now);
  });
  tearDown(() => db.close());

  Future<List<ItemWithStock>> list({
    String query = '',
    bool lowOnly = false,
    bool hidden = false,
  }) =>
      db.inventoryDao
          .watchItems('shop1',
              query: query, lowOnly: lowOnly, includeArchived: hidden)
          .first;

  Future<List<StockMovement>> movements(String itemId) => (db
          .select(db.stockMovements)
        ..where((t) => t.itemId.equals(itemId)))
      .get();

  group('create', () {
    test('opening stock becomes an opening movement; stock is derived',
        () async {
      final id = await repo.createItem(
        const ItemInput(
            name: 'Cheeni', unit: ItemUnit.kg, costPrice: 16500, salePrice: 18000),
        openingStock: 50000,
      );
      expect(await db.inventoryDao.stockOf(id), 50000);
      final m = await movements(id);
      expect(m, hasLength(1));
      expect(m.single.reason, StockReason.opening);
      expect(m.single.qty, 50000);
      final item = await db.inventoryDao.itemById(id);
      expect(item?.salePrice, 18000);
      expect(item?.name, 'Cheeni');
    });

    test('zero opening stock writes no movement', () async {
      final id = await repo.createItem(const ItemInput(name: 'Atta'));
      expect(await movements(id), isEmpty);
      expect(await db.inventoryDao.stockOf(id), 0);
    });

    test('validation: name required, no negatives', () async {
      await expectLater(repo.createItem(const ItemInput(name: '   ')),
          throwsA(isA<ItemValidationException>()));
      await expectLater(
          repo.createItem(const ItemInput(name: 'X', salePrice: -1)),
          throwsA(isA<ItemValidationException>()));
      await expectLater(
          repo.createItem(const ItemInput(name: 'X'), openingStock: -5),
          throwsA(isA<ItemValidationException>()));
      expect(await db.select(db.items).get(), isEmpty);
    });

    test('the item and its opening movement are queued for sync', () async {
      await repo.createItem(const ItemInput(name: 'Cheeni'),
          openingStock: 1000);
      final tables =
          (await db.outboxDao.nextBatch()).map((e) => e.entityTable).toList();
      expect(tables, ['items', 'stock_movements']);
    });
  });

  group('barcode', () {
    test('duplicate barcode is refused and points at the existing item',
        () async {
      final first = await repo.createItem(
          const ItemInput(name: 'Cheeni', barcode: '8961001'));
      await expectLater(
        repo.createItem(const ItemInput(name: 'Chini 2', barcode: ' 8961001 ')),
        throwsA(isA<DuplicateBarcodeException>()
            .having((e) => e.existingItemId, 'existingItemId', first)),
      );
      expect(await db.select(db.items).get(), hasLength(1));
    });

    test('a failed duplicate create leaves no outbox entries behind',
        () async {
      await repo.createItem(const ItemInput(name: 'A', barcode: '1'));
      final before = await db.outboxDao.pendingCount();
      await expectLater(
        repo.createItem(const ItemInput(name: 'B', barcode: '1'),
            openingStock: 1000),
        throwsA(isA<DuplicateBarcodeException>()),
      );
      expect(await db.outboxDao.pendingCount(), before);
    });

    test('editing may keep its own barcode but not take another item\'s',
        () async {
      final a = await repo.createItem(const ItemInput(name: 'A', barcode: '1'));
      final b = await repo.createItem(const ItemInput(name: 'B', barcode: '2'));
      await repo.updateItem(a, const ItemInput(name: 'A renamed', barcode: '1'));
      await expectLater(
        repo.updateItem(b, const ItemInput(name: 'B', barcode: '1')),
        throwsA(isA<DuplicateBarcodeException>()),
      );
    });

    test('items without a barcode never clash', () async {
      await repo.createItem(const ItemInput(name: 'A'));
      await repo.createItem(const ItemInput(name: 'B', barcode: '  '));
      await repo.createItem(const ItemInput(name: 'C'));
      expect(await db.select(db.items).get(), hasLength(3));
    });
  });

  group('update', () {
    test('editing details never changes stock', () async {
      final id = await repo.createItem(const ItemInput(name: 'Cheeni'),
          openingStock: 20000);
      await repo.updateItem(
          id, const ItemInput(name: 'Chini', salePrice: 19000, unit: ItemUnit.pack));
      expect(await db.inventoryDao.stockOf(id), 20000);
      expect(await movements(id), hasLength(1));
      final item = await db.inventoryDao.itemById(id);
      expect(item?.name, 'Chini');
      expect(item?.unit, ItemUnit.pack);
      expect(await db.inventoryDao.searchItemIds('shop1', 'chin'), [id]);
    });
  });

  group('adjustStock', () {
    test('records the difference as an adjustment with the reason', () async {
      final id = await repo.createItem(const ItemInput(name: 'Cheeni'),
          openingStock: 10000);

      await repo.adjustStock(id, 7500, 'Ginti mein kam nikla');
      expect(await db.inventoryDao.stockOf(id), 7500);

      await repo.adjustStock(id, 9000, 'Wapas mila');
      expect(await db.inventoryDao.stockOf(id), 9000);

      final adj = (await movements(id))
          .where((m) => m.reason == StockReason.adjustment)
          .toList();
      expect(adj.map((m) => m.qty).toSet(), {-2500, 1500});
      expect(adj.map((m) => m.note).toSet(),
          {'Ginti mein kam nikla', 'Wapas mila'});
    });

    test('same count writes nothing; negative count is refused', () async {
      final id = await repo.createItem(const ItemInput(name: 'Cheeni'),
          openingStock: 10000);
      final before = await db.outboxDao.pendingCount();
      await repo.adjustStock(id, 10000, 'same');
      expect(await movements(id), hasLength(1));
      expect(await db.outboxDao.pendingCount(), before);
      await expectLater(repo.adjustStock(id, -1, 'x'),
          throwsA(isA<ItemValidationException>()));
    });

    test('an adjustment is queued for sync', () async {
      final id = await repo.createItem(const ItemInput(name: 'Cheeni'));
      await repo.adjustStock(id, 5000, 'opening count');
      final last = (await db.outboxDao.nextBatch()).last;
      expect(last.entityTable, 'stock_movements');
    });
  });

  group('hide (archive)', () {
    test('hidden items leave the list but are never deleted', () async {
      final id = await repo.createItem(const ItemInput(name: 'Cheeni'),
          openingStock: 1000);
      await repo.createItem(const ItemInput(name: 'Atta'));

      await repo.setArchived(id, true);
      expect((await list()).map((e) => e.item.name), ['Atta']);
      expect((await list(hidden: true)).map((e) => e.item.name),
          ['Atta', 'Cheeni']);
      // History and stock survive.
      expect(await db.inventoryDao.stockOf(id), 1000);
      expect(await db.inventoryDao.itemById(id), isNotNull);

      await repo.setArchived(id, false);
      expect(await list(), hasLength(2));
    });
  });

  group('list', () {
    test('low stock is at or below the level', () async {
      await repo.createItem(
          const ItemInput(name: 'Cheeni', lowStockLevel: 10000),
          openingStock: 5000); // below
      await repo.createItem(
          const ItemInput(name: 'Daal', lowStockLevel: 3000),
          openingStock: 3000); // equal -> low
      await repo.createItem(
          const ItemInput(name: 'Chawal', lowStockLevel: 3000),
          openingStock: 80000); // fine

      final low = await list(lowOnly: true);
      expect(low.map((e) => e.item.name), ['Cheeni', 'Daal']);
      expect(low.every((e) => e.isLow), isTrue);
      expect((await list()).where((e) => e.isLow), hasLength(2));
    });

    test('search finds name prefixes', () async {
      await repo.createItem(const ItemInput(name: 'Cheeni'));
      await repo.createItem(const ItemInput(name: 'Chai patti'));
      await repo.createItem(const ItemInput(name: 'Atta'));
      expect((await list(query: 'che')).map((e) => e.item.name), ['Cheeni']);
      expect((await list(query: 'ch')).map((e) => e.item.name),
          ['Chai patti', 'Cheeni']);
      expect(await list(query: 'zzz'), isEmpty);
    });

    test('100 items can be added and are listed sorted by name', () async {
      for (var i = 0; i < 100; i++) {
        await repo.createItem(
          ItemInput(name: 'item ${i.toString().padLeft(3, '0')}'),
          openingStock: 1000,
        );
      }
      final items = await list();
      expect(items, hasLength(100));
      expect(items.first.item.name, 'item 000');
      expect(items.last.item.name, 'item 099');
      expect(items.every((e) => e.stock == 1000), isTrue);
    });
  });

  test('ftsPrefixQuery strips everything but letters and digits', () {
    expect(ftsPrefixQuery('che'), '"che"*');
    expect(ftsPrefixQuery('chai pa'), '"chai"* "pa"*');
    expect(ftsPrefixQuery('"; DROP'), '"DROP"*');
    expect(ftsPrefixQuery('  '), '');
  });
}
