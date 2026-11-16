import '../db/app_database.dart';

/// Tables that sync, in the order they are PULLED (parents before children:
/// shop, items, customers, suppliers, then sales, purchases, ledgers,
/// movements). `settings` is per device and only pulled on restore.
const syncTables = <String>[
  'shops',
  'items',
  'customers',
  'suppliers',
  'sales',
  'sale_lines',
  'sale_returns',
  'sale_return_lines',
  'purchases',
  'purchase_lines',
  'customer_ledger',
  'supplier_ledger',
  'stock_movements',
  'import_batches',
];

/// Pulled only when restoring on a new phone.
const restoreOnlyTables = <String>['settings'];

/// JSON keys that hold a DateTime in the local payload.
const _dateKeys = {'createdAt', 'updatedAt', 'date', 'undoneAt', 'lastSyncAt'};

/// Keys that are file paths on THIS phone. They are never sent to the server
/// and never taken from it; the remote copy is `photoUrl` /
/// `invoiceImageUrl`.
const localOnlyKeys = {'photoPath', 'invoiceImagePath'};

String toSnake(String camel) => camel.replaceAllMapped(
    RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

String toCamel(String snake) => snake.replaceAllMapped(
    RegExp(r'_([a-z0-9])'), (m) => m.group(1)!.toUpperCase());

/// Local outbox payload (`row.toJson()`: camelCase, DateTime as epoch ms or
/// ISO text) -> Postgres row (snake_case, ISO-8601 UTC timestamps).
Map<String, Object?> toServerRow(Map<String, Object?> payload) {
  final out = <String, Object?>{};
  payload.forEach((key, value) {
    if (localOnlyKeys.contains(key)) return;
    Object? v = value;
    if (_dateKeys.contains(key) && v != null) {
      if (v is int) {
        v = DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
            .toIso8601String();
      } else if (v is String) {
        v = DateTime.parse(v).toUtc().toIso8601String();
      }
    }
    out[toSnake(key)] = v;
  });
  return out;
}

/// Postgres row -> JSON accepted by the Drift data class `fromJson`.
/// [existingLocal] carries this phone's own file paths over (they are not on
/// the server).
Map<String, Object?> fromServerRow(
  Map<String, dynamic> row, {
  Map<String, Object?> existingLocal = const {},
}) {
  final out = <String, Object?>{};
  row.forEach((key, value) {
    if (key == 'server_updated_at') return;
    final k = toCamel(key);
    if (localOnlyKeys.contains(k)) return;
    Object? v = value;
    if (_dateKeys.contains(k) && v is String) {
      v = DateTime.parse(v).toUtc().millisecondsSinceEpoch;
    }
    out[k] = v;
  });
  for (final k in localOnlyKeys) {
    out[k] = existingLocal[k];
  }
  return out;
}

/// Writes one server row into the local database (no outbox: it came FROM
/// the server). Unique clashes caused by two offline phones are repaired
/// instead of failing the whole pull.
Future<void> applyServerRow(
    AppDatabase db, String table, Map<String, dynamic> serverRow) async {
  final id = serverRow['id'] as String;

  Future<Map<String, Object?>> existing() async {
    switch (table) {
      case 'items':
        final r = await db.inventoryDao.itemById(id);
        return r == null ? {} : r.toJson().cast<String, Object?>();
      case 'purchases':
        final r = await (db.select(db.purchases)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return r == null ? {} : r.toJson().cast<String, Object?>();
      case 'import_batches':
        final r = await (db.select(db.importBatches)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return r == null ? {} : r.toJson().cast<String, Object?>();
    }
    return {};
  }

  final json = fromServerRow(serverRow, existingLocal: await existing());

  Future<void> write(Map<String, Object?> j) async {
    switch (table) {
      case 'shops':
        await db.into(db.shops).insertOnConflictUpdate(Shop.fromJson(j));
      case 'items':
        await db.into(db.items).insertOnConflictUpdate(Item.fromJson(j));
      case 'customers':
        await db.into(db.customers).insertOnConflictUpdate(Customer.fromJson(j));
      case 'suppliers':
        await db.into(db.suppliers).insertOnConflictUpdate(Supplier.fromJson(j));
      case 'sales':
        await db.into(db.sales).insertOnConflictUpdate(Sale.fromJson(j));
      case 'sale_lines':
        await db.into(db.saleLines).insertOnConflictUpdate(SaleLine.fromJson(j));
      case 'sale_returns':
        await db
            .into(db.saleReturns)
            .insertOnConflictUpdate(SaleReturn.fromJson(j));
      case 'sale_return_lines':
        await db
            .into(db.saleReturnLines)
            .insertOnConflictUpdate(SaleReturnLine.fromJson(j));
      case 'purchases':
        await db.into(db.purchases).insertOnConflictUpdate(Purchase.fromJson(j));
      case 'purchase_lines':
        await db
            .into(db.purchaseLines)
            .insertOnConflictUpdate(PurchaseLine.fromJson(j));
      case 'customer_ledger':
        await db
            .into(db.customerLedger)
            .insertOnConflictUpdate(CustomerLedgerEntry.fromJson(j));
      case 'supplier_ledger':
        await db
            .into(db.supplierLedger)
            .insertOnConflictUpdate(SupplierLedgerEntry.fromJson(j));
      case 'stock_movements':
        await db
            .into(db.stockMovements)
            .insertOnConflictUpdate(StockMovement.fromJson(j));
      case 'import_batches':
        await db
            .into(db.importBatches)
            .insertOnConflictUpdate(ImportBatch.fromJson(j));
      case 'settings':
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(SettingsRow.fromJson(j));
      default:
        throw ArgumentError('Unknown sync table: $table');
    }
  }

  try {
    await write(json);
  } on Exception catch (e) {
    // Two offline phones made the same barcode or bill number.
    final text = e.toString();
    if (!text.contains('UNIQUE')) rethrow;
    if (table == 'items') {
      await write({...json, 'barcode': null});
    } else if (table == 'sales') {
      final short = id.substring(0, 4);
      await write({...json, 'billNo': '${json['billNo']}~$short'});
    } else {
      rethrow;
    }
  }
}
