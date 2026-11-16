import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/sync/sync_mapping.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';

void main() {
  test('snake / camel case', () {
    expect(toSnake('costPrice'), 'cost_price');
    expect(toSnake('shopId'), 'shop_id');
    expect(toCamel('cost_price'), 'costPrice');
    expect(toCamel('server_updated_at'), 'serverUpdatedAt');
  });

  test('push: dates become ISO text, local paths are never sent', () {
    final row = toServerRow({
      'id': 'a',
      'shopId': 's',
      'createdAt': DateTime.utc(2026, 11, 14, 10).millisecondsSinceEpoch,
      'photoPath': '/data/user/0/galla/photos/x.jpg',
      'photoUrl': 'https://x/y.jpg',
      'invoiceImagePath': '/p.jpg',
      'undoneAt': null,
    });
    expect(row['shop_id'], 's');
    expect(row['created_at'], '2026-11-14T10:00:00.000Z');
    expect(row.containsKey('photo_path'), isFalse);
    expect(row.containsKey('invoice_image_path'), isFalse);
    expect(row['photo_url'], 'https://x/y.jpg');
    expect(row['undone_at'], isNull);
  });

  test('pull: server row keeps this phone\'s own photo path', () {
    final json = fromServerRow({
      'id': 'a',
      'created_at': '2026-11-14T10:00:00+00:00',
      'photo_path': '/other/phone.jpg',
      'server_updated_at': '2026-11-14T10:00:01Z',
    }, existingLocal: {
      'photoPath': '/mine.jpg'
    });
    expect(json['photoPath'], '/mine.jpg');
    expect(json.containsKey('serverUpdatedAt'), isFalse);
    expect(json['createdAt'],
        DateTime.utc(2026, 11, 14, 10).millisecondsSinceEpoch);
  });

  test('a real row survives phone -> server -> phone', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final inv = InventoryRepository(
        db, () => 'shop1', () => DateTime(2026, 11, 14, 10));
    final id = await inv.createItem(
        const ItemInput(
            name: 'Cheeni',
            unit: ItemUnit.kg,
            costPrice: 16500,
            salePrice: 18000,
            barcode: '8961'),
        openingStock: 5000);
    final item = (await db.inventoryDao.itemById(id))!;

    final server = toServerRow(item.toJson().cast<String, Object?>());
    final back = Item.fromJson(fromServerRow(server));
    expect(back.id, item.id);
    expect(back.name, 'Cheeni');
    expect(back.costPrice, 16500);
    expect(back.barcode, '8961');
    expect(back.isArchived, isFalse);
    expect(back.createdAt.millisecondsSinceEpoch,
        item.createdAt.millisecondsSinceEpoch);
  });

  test('every synced table is known to applyServerRow', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final t in [...syncTables, ...restoreOnlyTables]) {
      await expectLater(
        applyServerRow(db, t, {'id': 'x'}).catchError((Object e) {
          // A missing column is fine here; an unknown table is not.
          expect(e, isNot(isA<ArgumentError>()));
        }),
        completes,
      );
    }
  });
}
