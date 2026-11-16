import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/config/app_info.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/utils/csv_writer.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';
import 'package:galla/features/settings/data/backup_service.dart';

void main() {
  group('csv writer', () {
    test('quotes commas, quotes and newlines', () {
      expect(toCsv([
        ['a,b', 'say "hi"', 'x\ny', 'plain']
      ]), '"a,b","say ""hi""","x\ny",plain\r\n');
    });

    test('formula-looking text is kept as text', () {
      expect(safeCell('=SUM(A1)'), "'=SUM(A1)");
      expect(safeCell('+92300'), "'+92300");
      expect(safeCell('@x'), "'@x");
      expect(safeCell('Akram'), 'Akram');
      expect(safeCell(''), '');
    });

    test('money and quantity cells are exact', () {
      expect(rupeesCell(340000), '3400.00');
      expect(rupeesCell(5), '0.05');
      expect(rupeesCell(-1250), '-12.50');
      expect(qtyCell(2500), '2.5');
      expect(qtyCell(25000), '25');
      expect(qtyCell(-1000), '-1');
      expect(qtyCell(1), '0.001');
    });
  });

  test('backup holds the whole shop and the numbers match the app', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 11, 14, 10, 30);
    await ShopRepository(db).createShop(
        shopId: 'shop1', shopName: 'S', phone: '+923001234567', now: now);
    final inv = InventoryRepository(db, () => 'shop1', () => now);
    final customers = CustomerRepository(db, () => 'shop1', () => now);
    final sales = SalesRepository(db, () => 'shop1', () => now);
    final cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni, sada',
            unit: ItemUnit.kg,
            costPrice: 16500,
            salePrice: 18000),
        openingStock: 50000);
    final ali = await customers.create(name: '=Ali', openingBalance: 25000);
    await sales.saveBill(BillInput(
        lines: [BillLineInput(itemId: cheeni, qty: 2500, unitPrice: 18000)],
        customerId: ali,
        credit: true));

    final files = await buildBackupFiles(db, 'shop1');
    expect(files.keys, containsAll([
      'customers.csv',
      'suppliers.csv',
      'items.csv',
      'sales.csv',
      'sale_lines.csv',
      'purchases.csv',
      'purchase_lines.csv',
      'customer_khata.csv',
      'supplier_khata.csv',
      'stock_movements.csv',
    ]));
    // Ali: opening 250.00 + bill 450.00 on udhaar = 700.00, name kept as text.
    expect(files['customers.csv'], contains("'=Ali,,700.00,no"));
    // Stock 50 - 2.5 = 47.5; name with a comma is quoted.
    expect(files['items.csv'], contains('"Cheeni, sada",,kg,165.00,180.00,47.5,0,no'));
    expect(files['sales.csv'], contains('450.00'));
    expect(files['sale_lines.csv'], contains('2.5'));
    // Header rows exist even for empty tables.
    expect(files['suppliers.csv'], startsWith('name,phone,balance_rs,hidden'));
  });

  test('another shop\'s rows never leak into the backup', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 11, 14);
    await ShopRepository(db)
        .createShop(shopId: 'shop1', shopName: 'S1', phone: '+923001234567', now: now);
    await ShopRepository(db)
        .createShop(shopId: 'shop2', shopName: 'S2', phone: '+923001234568', now: now);
    await CustomerRepository(db, () => 'shop2', () => now).create(name: 'Other');
    final files = await buildBackupFiles(db, 'shop1');
    expect(files['customers.csv'], isNot(contains('Other')));
  });

  test('AppInfo.version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true)
        .firstMatch(pubspec);
    expect(m?.group(1), AppInfo.version);
  });
}
