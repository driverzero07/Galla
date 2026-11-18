import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';

void main() {
  test('a version 1 database upgrades to the current version without losing '
      'data', () async {
    // A phone that installed Part 1: stock_movements has no `note` column.
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      // Every Part 1 phone already has its shop row.
      raw.execute('''
        CREATE TABLE shops (
          id TEXT NOT NULL, shop_id TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          name TEXT NOT NULL, owner_name TEXT NULL, phone TEXT NOT NULL,
          PRIMARY KEY (id))
      ''');
      raw.execute("INSERT INTO shops VALUES "
          "('s1','s1',1,1,'Old Store',NULL,'+923001234567')");
      raw.execute('''
        CREATE TABLE stock_movements (
          id TEXT NOT NULL, shop_id TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          item_id TEXT NOT NULL, qty INTEGER NOT NULL, reason TEXT NOT NULL,
          ref_type TEXT NULL, ref_id TEXT NULL, PRIMARY KEY (id))
      ''');
      raw.execute('''
        CREATE TABLE sale_returns (
          id TEXT NOT NULL, shop_id TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          sale_id TEXT NOT NULL, amount INTEGER NOT NULL, PRIMARY KEY (id))
      ''');
      raw.execute('''
        CREATE TABLE purchases (
          id TEXT NOT NULL, shop_id TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          supplier_id TEXT NOT NULL, total INTEGER NOT NULL,
          paid_amount INTEGER NOT NULL DEFAULT 0,
          invoice_image_path TEXT NULL, invoice_image_url TEXT NULL,
          status TEXT NOT NULL DEFAULT 'active', PRIMARY KEY (id))
      ''');
      raw.execute("INSERT INTO purchases (id, shop_id, created_at, updated_at, "
          "supplier_id, total) VALUES ('p1','s1',1,1,'sup',5000)");
      raw.execute("INSERT INTO sale_returns VALUES ('r1','s1',1,1,'x',700)");
      raw.execute("INSERT INTO stock_movements VALUES "
          "('m1','s1',1,1,'i1',5000,'opening',NULL,NULL)");
      raw.execute('PRAGMA user_version = 1');
    }));
    addTearDown(db.close);

    final cols = await db
        .customSelect("SELECT name FROM pragma_table_info('stock_movements')")
        .get();
    expect(cols.map((r) => r.read<String>('name')), contains('note'));

    final old = await db.select(db.stockMovements).get();
    expect(old.single.qty, 5000);
    expect(old.single.note, isNull);

    final rc = await db
        .customSelect("SELECT name FROM pragma_table_info('sale_returns')")
        .get();
    expect(rc.map((r) => r.read<String>('name')),
        containsAll(['ledger_credit', 'cash_refund', 'note']));
    final ret = await db.select(db.saleReturns).get();
    expect(ret.single.amount, 700);
    expect(ret.single.ledgerCredit, 0);

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(tables.map((r) => r.read<String>('name')), contains('device_state'));

    final pc = await db
        .customSelect("SELECT name FROM pragma_table_info('purchases')")
        .get();
    expect(pc.map((r) => r.read<String>('name')), contains('purchase_no'));
    final purchase = await db.select(db.purchases).get();
    expect(purchase.single.total, 5000);
    expect(purchase.single.purchaseNo, '');

    final ib = await db
        .customSelect("SELECT name FROM pragma_table_info('import_batches')")
        .get();
    expect(ib.map((r) => r.read<String>('name')),
        containsAll(['kind', 'method', 'row_count', 'entity_ids', 'undone_at']));

    final sc = await db
        .customSelect("SELECT name FROM pragma_table_info('shops')")
        .get();
    expect(sc.map((r) => r.read<String>('name')), contains('opening_cash'));
    final shop = await db.select(db.shops).getSingle();
    expect(shop.name, 'Old Store');
    expect(shop.openingCash, 0);

    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), AppDatabase.currentSchemaVersion);
  });
}
