import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/inventory_dao.dart';
import 'daos/khata_dao.dart';
import 'daos/device_state_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/purchases_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/shop_dao.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Shops,
    Items,
    StockMovements,
    Customers,
    CustomerLedger,
    Suppliers,
    SupplierLedger,
    Sales,
    SaleLines,
    SaleReturns,
    SaleReturnLines,
    Purchases,
    PurchaseLines,
    Outbox,
    AppSettings,
    DeviceState,
    ImportBatches,
  ],
  daos: [
    PurchasesDao,
    OutboxDao,
    ShopDao,
    InventoryDao,
    KhataDao,
    SalesDao,
    DeviceStateDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Production database (SQLite file in app storage).
  AppDatabase.open() : super(driftDatabase(name: 'galla'));

  /// For tests: pass `NativeDatabase.memory()`.
  AppDatabase(super.executor);

  static const currentSchemaVersion = 5;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createItemSearch();
        },
        onUpgrade: (m, from, to) async {
          // Migration strategy: bump [currentSchemaVersion], then add one
          // `if (from < N) { ... }` block per version, using
          // m.addColumn / m.createTable / customStatement. Never edit or
          // drop an old block, so a phone on any old version can step up.
          //
          if (from < 2) {
            // Part 2: reason text for stock corrections.
            await m.addColumn(stockMovements, stockMovements.note);
          }
          if (from < 3) {
            // Part 3: local device state, and return bookkeeping.
            await m.createTable(deviceState);
            await m.addColumn(saleReturns, saleReturns.ledgerCredit);
            await m.addColumn(saleReturns, saleReturns.cashRefund);
            await m.addColumn(saleReturns, saleReturns.note);
          }
          if (from < 4) {
            // Part 4: purchase numbers.
            await m.addColumn(purchases, purchases.purchaseNo);
          }
          if (from < 5) {
            // Part 6: import batches.
            await m.createTable(importBatches);
          }
          // Next: if (from < 6) { ... }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// FTS5 index over item names, kept in sync by triggers. Drift does not
  /// know about it; query it through [InventoryDao.searchItemIds].
  Future<void> _createItemSearch() async {
    await customStatement(
      "CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5("
      "name, content='items', content_rowid='rowid', "
      "tokenize='unicode61 remove_diacritics 2')",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS items_fts_ai AFTER INSERT ON items BEGIN '
      'INSERT INTO items_fts(rowid, name) VALUES (new.rowid, new.name); END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS items_fts_ad AFTER DELETE ON items BEGIN '
      "INSERT INTO items_fts(items_fts, rowid, name) "
      "VALUES ('delete', old.rowid, old.name); END",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS items_fts_au AFTER UPDATE ON items BEGIN '
      "INSERT INTO items_fts(items_fts, rowid, name) "
      "VALUES ('delete', old.rowid, old.name); "
      'INSERT INTO items_fts(rowid, name) VALUES (new.rowid, new.name); END',
    );
  }
}
