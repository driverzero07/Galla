import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/sync/sync_mapping.dart';
import 'package:galla/core/sync/sync_service.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/bill/data/sales_repository.dart';
import 'package:galla/features/customers/data/party_repository.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';
import 'package:galla/features/khata/data/khata_repository.dart';
import 'package:galla/features/purchase/data/purchase_repository.dart';

import 'fake_remote.dart';

/// Integration: a whole day with no internet (setup, stock, bills on cash and
/// udhaar, a payment, a return, a cancelled bill, a purchase, a stock
/// count), then the net comes back and the server must match the phone.
void main() {
  test('a full offline day syncs and the server matches the phone', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final remote = FakeRemote();
    var clock = DateTime(2026, 11, 14, 9);
    DateTime now() => clock;
    final sync = SyncService(db, remote, () => 'shop1', now: now);

    await ShopRepository(db).createShop(
        shopId: 'shop1',
        shopName: 'Ali General Store',
        phone: '+923001234567',
        now: clock);
    final inv = InventoryRepository(db, () => 'shop1', now);
    final customers = CustomerRepository(db, () => 'shop1', now);
    final suppliers = SupplierRepository(db, () => 'shop1', now);
    final sales = SalesRepository(db, () => 'shop1', now, random: Random(5));
    final khata = KhataRepository(db, () => 'shop1', now);
    final purchases =
        PurchaseRepository(db, () => 'shop1', now, random: Random(6));

    final cheeni = await inv.createItem(
        const ItemInput(
            name: 'Cheeni',
            unit: ItemUnit.kg,
            costPrice: 16500,
            salePrice: 18000),
        openingStock: 80000);
    final chai = await inv.createItem(
        const ItemInput(
            name: 'Chai',
            unit: ItemUnit.pack,
            costPrice: 40000,
            salePrice: 45000),
        openingStock: 20000);
    final ali = await customers.create(name: 'Ali', openingBalance: 100000);
    final sara = await customers.create(name: 'Sara');
    final sheikh = await suppliers.create(name: 'Sheikh Traders');

    clock = clock.add(const Duration(hours: 1));
    final cash = await sales.saveBill(BillInput(
        lines: [BillLineInput(itemId: cheeni, qty: 2000, unitPrice: 18000)]));
    final udhaar = await sales.saveBill(BillInput(
        lines: [
          BillLineInput(itemId: cheeni, qty: 5000, unitPrice: 18000),
          BillLineInput(itemId: chai, qty: 1000, unitPrice: 45000),
        ],
        customerId: ali,
        credit: true));
    final toCancel = await sales.saveBill(BillInput(
        lines: [BillLineInput(itemId: chai, qty: 2000, unitPrice: 45000)],
        customerId: sara,
        credit: true));
    clock = clock.add(const Duration(hours: 1));
    await khata.receivePayment(ali, 50000);
    await sales.createReturn(udhaar.saleId, {cheeni: 1000});
    await sales.cancelSale(toCancel.saleId);
    await purchases.savePurchase(PurchaseInput(
        supplierId: sheikh,
        lines: [PurchaseLineInput(itemId: cheeni, qty: 30000, unitCost: 16000)],
        paidNow: 100000));
    await inv.adjustStock(chai, 17000, StockReason.adjustment);
    expect(cash.saleId, isNotEmpty);

    expect(await db.outboxDao.pendingCount(), greaterThan(20));

    // The net comes back.
    clock = clock.add(const Duration(hours: 2));
    expect(await sync.syncNow(reason: 'reconnect'), isTrue);
    expect(await db.outboxDao.pendingCount(), 0);

    // 1. Same number of rows in every synced table.
    final local = <String, int>{
      'shops': (await db.select(db.shops).get()).length,
      'items': (await db.select(db.items).get()).length,
      'customers': (await db.select(db.customers).get()).length,
      'suppliers': (await db.select(db.suppliers).get()).length,
      'sales': (await db.select(db.sales).get()).length,
      'sale_lines': (await db.select(db.saleLines).get()).length,
      'sale_returns': (await db.select(db.saleReturns).get()).length,
      'sale_return_lines': (await db.select(db.saleReturnLines).get()).length,
      'purchases': (await db.select(db.purchases).get()).length,
      'purchase_lines': (await db.select(db.purchaseLines).get()).length,
      'customer_ledger': (await db.select(db.customerLedger).get()).length,
      'supplier_ledger': (await db.select(db.supplierLedger).get()).length,
      'stock_movements': (await db.select(db.stockMovements).get()).length,
    };
    for (final t in syncTables) {
      if (!local.containsKey(t)) continue;
      expect(remote.count(t), local[t], reason: 'rows in $t');
    }

    // 2. The server's own rows give the same khata and stock as the phone.
    int sumBy(String table, String idKey, String valueKey, String id) =>
        remote.tables[table]!.values
            .where((r) => r[idKey] == id)
            .fold<int>(0, (s, r) => s + (r[valueKey] as int));
    for (final c in [ali, sara]) {
      expect(sumBy('customer_ledger', 'customer_id', 'amount', c),
          await db.khataDao.customerBalance(c),
          reason: 'khata of $c');
    }
    expect(sumBy('supplier_ledger', 'supplier_id', 'amount', sheikh),
        await db.khataDao.supplierBalance(sheikh));
    for (final i in [cheeni, chai]) {
      expect(sumBy('stock_movements', 'item_id', 'qty', i),
          await db.inventoryDao.stockOf(i),
          reason: 'stock of $i');
    }

    // 3. Bill totals match, and the cancelled bill is cancelled on the server.
    final localTotal = (await db.select(db.sales).get())
        .fold<int>(0, (s, e) => s + e.total);
    final serverTotal = remote.tables['sales']!.values
        .fold<int>(0, (s, r) => s + (r['total'] as int));
    expect(serverTotal, localTotal);
    expect(remote.tables['sales']![toCancel.saleId]!['status'],
        DocStatus.cancelled);

    // 4. A second sync with nothing new is quiet.
    final calls = remote.upserts.length;
    clock = clock.add(const Duration(minutes: 10));
    expect(await sync.syncNow(reason: 'timer'), isTrue);
    expect(remote.upserts.length, calls);
  });
}
