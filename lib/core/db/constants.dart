/// String constants for enum-like text columns. Plain strings (not Dart
/// enums) so rows sync to Postgres unchanged.
abstract final class ItemUnit {
  static const kg = 'kg';
  static const pack = 'pack';
  static const dozen = 'dozen';
  static const piece = 'piece';
  static const all = [kg, pack, dozen, piece];
}

abstract final class StockReason {
  static const opening = 'opening';
  static const sale = 'sale';
  static const purchase = 'purchase';
  static const returnIn = 'return_in';
  static const cancelSale = 'cancel_sale';
  static const adjustment = 'adjustment';
}

abstract final class CustomerLedgerType {
  static const opening = 'opening';
  static const saleCredit = 'sale_credit';
  static const paymentReceived = 'payment_received';
  static const manualUdhaar = 'manual_udhaar';
  static const returnCredit = 'return_credit';
  static const adjustment = 'adjustment';
}

abstract final class SupplierLedgerType {
  static const opening = 'opening';
  static const purchaseCredit = 'purchase_credit';
  static const paymentMade = 'payment_made';
  static const adjustment = 'adjustment';
}

abstract final class PaymentMode {
  static const cash = 'cash';
  static const udhaar = 'udhaar';
  static const partial = 'partial';
}

abstract final class DocStatus {
  static const active = 'active';
  static const cancelled = 'cancelled';
}

abstract final class OutboxOp {
  /// Every synced write is an idempotent upsert by UUID. `insert` vs
  /// `update` is kept for diagnostics only.
  static const insert = 'insert';
  static const update = 'update';
}

abstract final class ImportKind {
  static const customers = 'customers';
  static const suppliers = 'suppliers';
  static const items = 'items';
}

abstract final class ImportMethod {
  static const quick = 'quick';
  static const file = 'file';
  static const ocr = 'ocr';
}

abstract final class AppLanguage {
  static const romanUrdu = 'roman_urdu';
}
