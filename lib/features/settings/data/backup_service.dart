import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/utils/csv_writer.dart';
import '../../auth/domain/current_shop.dart';

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

List<T> _byDate<T>(List<T> l, DateTime Function(T) f) =>
    [...l]..sort((a, b) => f(a).compareTo(f(b)));

/// Builds the CSV backup: one file per kind of data, readable in Excel. Pure
/// reads, so it is safe to run any time and easy to test. File name -> text.
Future<Map<String, String>> buildBackupFiles(
    AppDatabase db, String shopId) async {
  final customers = await (db.select(db.customers)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final suppliers = await (db.select(db.suppliers)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final items = await (db.select(db.items)..where((t) => t.shopId.equals(shopId)))
      .get();
  final sales = await (db.select(db.sales)..where((t) => t.shopId.equals(shopId)))
      .get();
  final saleLines = await (db.select(db.saleLines)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final purchases = await (db.select(db.purchases)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final purchaseLines = await (db.select(db.purchaseLines)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final cLedger = await (db.select(db.customerLedger)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final sLedger = await (db.select(db.supplierLedger)
        ..where((t) => t.shopId.equals(shopId)))
      .get();
  final moves = await (db.select(db.stockMovements)
        ..where((t) => t.shopId.equals(shopId)))
      .get();

  final customerName = {for (final c in customers) c.id: c.name};
  final supplierName = {for (final s in suppliers) s.id: s.name};
  final itemName = {for (final i in items) i.id: i.name};
  final saleNo = {for (final s in sales) s.id: s.billNo};
  final purchaseNo = {for (final p in purchases) p.id: p.purchaseNo};

  final cBal = <String, int>{};
  for (final l in cLedger) {
    cBal[l.customerId] = (cBal[l.customerId] ?? 0) + l.amount;
  }
  final sBal = <String, int>{};
  for (final l in sLedger) {
    sBal[l.supplierId] = (sBal[l.supplierId] ?? 0) + l.amount;
  }
  final stock = <String, int>{};
  for (final m in moves) {
    stock[m.itemId] = (stock[m.itemId] ?? 0) + m.qty;
  }

  String yn(bool b) => b ? 'yes' : 'no';

  return {
    'customers.csv': toCsv([
      ['name', 'phone', 'balance_rs', 'hidden'],
      for (final c in customers)
        [safeCell(c.name), safeCell(c.phone ?? ''), rupeesCell(cBal[c.id] ?? 0), yn(c.isArchived)],
    ]),
    'suppliers.csv': toCsv([
      ['name', 'phone', 'balance_rs', 'hidden'],
      for (final s in suppliers)
        [safeCell(s.name), safeCell(s.phone ?? ''), rupeesCell(sBal[s.id] ?? 0), yn(s.isArchived)],
    ]),
    'items.csv': toCsv([
      ['name', 'barcode', 'unit', 'cost_rs', 'price_rs', 'stock', 'low_stock_level', 'hidden'],
      for (final i in items)
        [
          safeCell(i.name),
          safeCell(i.barcode ?? ''),
          i.unit,
          rupeesCell(i.costPrice),
          rupeesCell(i.salePrice),
          qtyCell(stock[i.id] ?? 0),
          qtyCell(i.lowStockLevel),
          yn(i.isArchived),
        ],
    ]),
    'sales.csv': toCsv([
      ['bill_no', 'date', 'customer', 'subtotal_rs', 'discount_rs', 'total_rs', 'paid_rs', 'payment_mode', 'status'],
      for (final s in _byDate(sales, (s) => s.createdAt))
        [
          s.billNo,
          _stamp(s.createdAt),
          safeCell(customerName[s.customerId] ?? ''),
          rupeesCell(s.subtotal),
          rupeesCell(s.discount),
          rupeesCell(s.total),
          rupeesCell(s.paidAmount),
          s.paymentMode,
          s.status,
        ],
    ]),
    'sale_lines.csv': toCsv([
      ['bill_no', 'item', 'qty', 'unit_price_rs', 'line_total_rs'],
      for (final l in saleLines)
        [
          saleNo[l.saleId] ?? '',
          safeCell(l.nameSnapshot),
          qtyCell(l.qty),
          rupeesCell(l.unitPrice),
          rupeesCell(l.lineTotal),
        ],
    ]),
    'purchases.csv': toCsv([
      ['purchase_no', 'date', 'supplier', 'total_rs', 'paid_rs', 'status'],
      for (final p in _byDate(purchases, (p) => p.createdAt))
        [
          p.purchaseNo,
          _stamp(p.createdAt),
          safeCell(supplierName[p.supplierId] ?? ''),
          rupeesCell(p.total),
          rupeesCell(p.paidAmount),
          p.status,
        ],
    ]),
    'purchase_lines.csv': toCsv([
      ['purchase_no', 'item', 'qty', 'unit_cost_rs'],
      for (final l in purchaseLines)
        [
          purchaseNo[l.purchaseId] ?? '',
          safeCell(itemName[l.itemId] ?? ''),
          qtyCell(l.qty),
          rupeesCell(l.unitCost),
        ],
    ]),
    'customer_khata.csv': toCsv([
      ['date', 'customer', 'type', 'amount_rs', 'note'],
      for (final l in _byDate(cLedger, (l) => l.date))
        [
          _stamp(l.date),
          safeCell(customerName[l.customerId] ?? ''),
          l.type,
          rupeesCell(l.amount),
          safeCell(l.note ?? ''),
        ],
    ]),
    'supplier_khata.csv': toCsv([
      ['date', 'supplier', 'type', 'amount_rs', 'note'],
      for (final l in _byDate(sLedger, (l) => l.date))
        [
          _stamp(l.date),
          safeCell(supplierName[l.supplierId] ?? ''),
          l.type,
          rupeesCell(l.amount),
          safeCell(l.note ?? ''),
        ],
    ]),
    'stock_movements.csv': toCsv([
      ['date', 'item', 'qty', 'reason', 'note'],
      for (final m in _byDate(moves, (m) => m.createdAt))
        [
          _stamp(m.createdAt),
          safeCell(itemName[m.itemId] ?? ''),
          qtyCell(m.qty),
          m.reason,
          safeCell(m.note ?? ''),
        ],
    ]),
  };
}

class BackupService {
  BackupService(this._db, this._shopId);

  final AppDatabase _db;
  final String Function() _shopId;

  /// Writes the CSV files to a temporary folder and opens the share sheet
  /// (WhatsApp, Drive, email...). Returns how many files were shared.
  Future<int> exportAndShare() async {
    final files = await buildBackupFiles(_db, _shopId());
    final dir = await getTemporaryDirectory();
    final out = Directory('${dir.path}/galla_backup');
    if (await out.exists()) await out.delete(recursive: true);
    await out.create(recursive: true);
    final xfiles = <XFile>[];
    for (final e in files.entries) {
      final f = File('${out.path}/${e.key}');
      // UTF-8 with BOM so Excel shows Urdu names correctly.
      await f.writeAsString('${String.fromCharCode(0xFEFF)}${e.value}');
      xfiles.add(XFile(f.path, mimeType: 'text/csv'));
    }
    await Share.shareXFiles(xfiles, subject: 'Galla backup');
    return xfiles.length;
  }
}

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
      ref.watch(appDatabaseProvider),
      () => ref.read(shopIdProvider),
    ));
