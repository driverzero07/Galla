import 'package:drift/drift.dart';

/// Columns shared by every synced table: client-generated UUID id, shop_id,
/// created_at, updated_at.
mixin BaseColumns on Table {
  TextColumn get id => text()();
  TextColumn get shopId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

// Money = integer paisa. Quantity = integer thousandths (2.5 kg = 2500).

class Shops extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get ownerName => text().nullable()();
  TextColumn get phone => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_items_shop_barcode', columns: {#shopId, #barcode})
@TableIndex(name: 'idx_items_shop_name', columns: {#shopId, #name})
class Items extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('kg'))();
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  IntColumn get salePrice => integer().withDefault(const Constant(0))();
  IntColumn get lowStockLevel => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  /// Barcode is unique per shop. SQLite treats NULLs as distinct, so items
  /// without a barcode never clash.
  @override
  List<Set<Column>> get uniqueKeys => [
        {shopId, barcode},
      ];
}

@TableIndex(name: 'idx_stock_movements_item', columns: {#itemId})
class StockMovements extends Table with BaseColumns {
  TextColumn get itemId => text()();

  /// Signed quantity thousandths: + stock in, - stock out.
  IntColumn get qty => integer()();

  /// opening | sale | purchase | return_in | cancel_sale | adjustment
  TextColumn get reason => text()();
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();

  /// Free text, e.g. the reason given for a stock correction (schema v2).
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Customers extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CustomerLedgerEntry')
@TableIndex(name: 'idx_customer_ledger_customer', columns: {#customerId})
class CustomerLedger extends Table with BaseColumns {
  TextColumn get customerId => text()();

  /// opening | sale_credit | payment_received | manual_udhaar |
  /// return_credit | adjustment
  TextColumn get type => text()();

  /// Signed paisa: + means the customer owes more.
  IntColumn get amount => integer()();
  TextColumn get refId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Suppliers extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SupplierLedgerEntry')
@TableIndex(name: 'idx_supplier_ledger_supplier', columns: {#supplierId})
class SupplierLedger extends Table with BaseColumns {
  TextColumn get supplierId => text()();

  /// opening | purchase_credit | payment_made | adjustment
  TextColumn get type => text()();

  /// Signed paisa: + means we owe the supplier more.
  IntColumn get amount => integer()();
  TextColumn get refId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_sales_shop_created', columns: {#shopId, #createdAt})
@TableIndex(name: 'idx_sales_customer', columns: {#customerId})
class Sales extends Table with BaseColumns {
  TextColumn get billNo => text()();
  TextColumn get customerId => text()();
  IntColumn get subtotal => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();

  /// cash | udhaar | partial
  TextColumn get paymentMode => text()();

  /// active | cancelled
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {shopId, billNo},
      ];
}

@TableIndex(name: 'idx_sale_lines_sale', columns: {#saleId})
@TableIndex(name: 'idx_sale_lines_item', columns: {#itemId})
class SaleLines extends Table with BaseColumns {
  TextColumn get saleId => text()();
  TextColumn get itemId => text()();
  TextColumn get nameSnapshot => text()();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get costSnapshot => integer()();
  IntColumn get lineTotal => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleReturns extends Table with BaseColumns {
  TextColumn get saleId => text()();

  /// Total value of the returned goods in paisa (= ledgerCredit + cashRefund).
  IntColumn get amount => integer()();

  /// Part of [amount] taken off the customer's khata (schema v3).
  IntColumn get ledgerCredit => integer().withDefault(const Constant(0))();

  /// Part of [amount] handed back in cash: the "cash refund note" (v3).
  IntColumn get cashRefund => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleReturnLines extends Table with BaseColumns {
  TextColumn get returnId => text()();
  TextColumn get saleId => text()();
  TextColumn get itemId => text()();
  IntColumn get qty => integer()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_purchases_supplier', columns: {#supplierId})
class Purchases extends Table with BaseColumns {
  TextColumn get supplierId => text()();

  /// "XXX-n" like bill numbers (schema v4). Empty on rows made before v4.
  TextColumn get purchaseNo => text().withDefault(const Constant(''))();
  IntColumn get total => integer()();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
  TextColumn get invoiceImagePath => text().nullable()();
  TextColumn get invoiceImageUrl => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_purchase_lines_purchase', columns: {#purchaseId})
class PurchaseLines extends Table with BaseColumns {
  TextColumn get purchaseId => text()();
  TextColumn get itemId => text()();
  IntColumn get qty => integer()();
  IntColumn get unitCost => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending changes waiting to be pushed to Supabase, in insertion order.
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Dart name avoids clashing with Table.tableName; SQL column is table_name.
  TextColumn get entityTable => text().named('table_name')();
  TextColumn get rowId => text()();

  /// insert | update (the server applies an idempotent upsert either way)
  TextColumn get op => text()();

  /// JSON of the full row.
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

/// One row per shop. Table name is `settings`.
@DataClassName('SettingsRow')
class AppSettings extends Table with BaseColumns {
  @override
  String get tableName => 'settings';

  TextColumn get language =>
      text().withDefault(const Constant('roman_urdu'))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  IntColumn get pinLockMinutes => integer().withDefault(const Constant(5))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-only key/value store (NOT synced, never goes through the outbox):
/// this device's bill-number prefix and sequence, and the unsaved bill draft.
@DataClassName('DeviceStateEntry')
class DeviceState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// One migration from the paper copy (Part 6). Every created row is listed in
/// [entityIds] so the whole batch can be undone. Opening balances and opening
/// stock rows carry this batch id as their `ref_id`.
@DataClassName('ImportBatch')
class ImportBatches extends Table with BaseColumns {
  /// customers | suppliers | items
  TextColumn get kind => text()();

  /// quick | file | ocr
  TextColumn get method => text()();
  IntColumn get rowCount => integer()();

  /// Sum of opening balances in paisa (0 for items).
  IntColumn get totalAmount => integer().withDefault(const Constant(0))();

  /// JSON array of the ids of customers / suppliers / items created.
  TextColumn get entityIds => text()();

  /// Photo of the paper copy, kept as proof (OCR method).
  TextColumn get photoPath => text().nullable()();
  DateTimeColumn get undoneAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
