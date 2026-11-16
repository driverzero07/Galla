import '../../../core/db/constants.dart';
import '../../../core/utils/phone.dart';
import 'import_numbers.dart';

/// What is wrong or doubtful about one row on the confirm screen.
enum RowIssue {
  /// Cannot be imported until fixed (empty name, unreadable amount).
  error,

  /// Readable but "Pakka nahi, check karo".
  uncertain,

  /// Same name and phone already exists, or appears twice in this batch.
  duplicate,
}

/// Lower-case, single-spaced name used to compare people.
String normalizeName(String s) =>
    normalizeDigits(s).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Name + phone key for duplicate checks. A missing phone is part of the key
/// (two "Akram" with no phone are the same person as far as we can tell).
String partyKey(String name, String phone) {
  final p = phone.trim().isEmpty ? '' : (normalizePkPhone(phone) ?? phone.trim());
  return '${normalizeName(name)}|$p';
}

/// A customer or supplier line on the confirm screen. Everything the owner
/// can edit is kept as text so what they see is what is imported.
class PartyImportRow {
  const PartyImportRow({
    required this.id,
    this.name = '',
    this.phone = '',
    this.amount = '',
    this.include = true,
    this.sourceUncertain = false,
    this.keepDuplicate = false,
  });

  final int id;
  final String name;
  final String phone;
  final String amount;
  final bool include;

  /// The source was unsure (OCR confidence, a "?" on paper). Cleared once
  /// the owner edits the row.
  final bool sourceUncertain;

  /// The owner chose to import this duplicate anyway.
  final bool keepDuplicate;

  bool get isBlank =>
      name.trim().isEmpty && phone.trim().isEmpty && amount.trim().isEmpty;

  PartyImportRow copyWith({
    String? name,
    String? phone,
    String? amount,
    bool? include,
    bool? sourceUncertain,
    bool? keepDuplicate,
  }) =>
      PartyImportRow(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        amount: amount ?? this.amount,
        include: include ?? this.include,
        sourceUncertain: sourceUncertain ?? this.sourceUncertain,
        keepDuplicate: keepDuplicate ?? this.keepDuplicate,
      );
}

/// The verdict for one party row.
class PartyAssessment {
  const PartyAssessment({
    required this.issues,
    required this.paisa,
    required this.phone,
    this.nameKey = '',
  });

  final Set<RowIssue> issues;

  /// Signed opening balance in paisa (0 when unreadable).
  final int paisa;

  /// Normalised phone to save, or null.
  final String? phone;
  final String nameKey;

  bool get hasError => issues.contains(RowIssue.error);
  bool get isUncertain => issues.contains(RowIssue.uncertain);
  bool get isDuplicate => issues.contains(RowIssue.duplicate);
}

const maxOpeningBalance = 100000000000; // Rs 1,000,000,000 in paisa

PartyAssessment assessParty(
  PartyImportRow row, {
  required Set<String> existingKeys,
  required Set<String> seenInBatch,
}) {
  final issues = <RowIssue>{};
  final name = row.name.trim();
  if (name.isEmpty) issues.add(RowIssue.error);
  if (name.length == 1) issues.add(RowIssue.uncertain);

  final amount = parseImportAmount(row.amount);
  if (amount.error) issues.add(RowIssue.error);
  if (amount.uncertain || amount.paisa < 0) issues.add(RowIssue.uncertain);
  if (amount.paisa.abs() > maxOpeningBalance) issues.add(RowIssue.error);

  String? phone;
  if (row.phone.trim().isNotEmpty) {
    phone = normalizePkPhone(row.phone);
    if (phone == null) issues.add(RowIssue.uncertain);
  }
  if (row.sourceUncertain) issues.add(RowIssue.uncertain);

  final key = partyKey(name, row.phone);
  if (name.isNotEmpty &&
      (existingKeys.contains(key) || seenInBatch.contains(key))) {
    issues.add(RowIssue.duplicate);
  }
  return PartyAssessment(
    issues: issues,
    paisa: amount.error ? 0 : amount.paisa,
    phone: phone,
    nameKey: key,
  );
}

/// Assesses every row in order, so a name repeated inside the batch is
/// flagged on its second appearance only.
List<PartyAssessment> assessAllParties(
  List<PartyImportRow> rows, {
  required Set<String> existingKeys,
}) {
  final seen = <String>{};
  final out = <PartyAssessment>[];
  for (final r in rows) {
    final a = assessParty(r, existingKeys: existingKeys, seenInBatch: seen);
    if (r.include && !a.hasError && a.nameKey.isNotEmpty) seen.add(a.nameKey);
    out.add(a);
  }
  return out;
}

/// An item line on the confirm screen (CSV / Excel only).
class ItemImportRow {
  const ItemImportRow({
    required this.id,
    this.name = '',
    this.unit = '',
    this.cost = '',
    this.price = '',
    this.stock = '',
    this.low = '',
    this.barcode = '',
    this.include = true,
    this.keepDuplicate = false,
  });

  final int id;
  final String name;
  final String unit;
  final String cost;
  final String price;
  final String stock;
  final String low;
  final String barcode;
  final bool include;
  final bool keepDuplicate;

  ItemImportRow copyWith({
    String? name,
    String? unit,
    String? cost,
    String? price,
    String? stock,
    String? low,
    String? barcode,
    bool? include,
    bool? keepDuplicate,
  }) =>
      ItemImportRow(
        id: id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        cost: cost ?? this.cost,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        low: low ?? this.low,
        barcode: barcode ?? this.barcode,
        include: include ?? this.include,
        keepDuplicate: keepDuplicate ?? this.keepDuplicate,
      );
}

/// Maps unit words from sheets ("Kilo", "pcs", "dana") to [ItemUnit].
/// Null when the text is not recognised.
String? mapUnit(String raw) {
  final t = normalizeName(raw);
  if (t.isEmpty) return null;
  const kg = {'kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms', 'k.g'};
  const pack = {'pack', 'packs', 'packet', 'packets', 'pkt', 'box', 'carton'};
  const dozen = {'dozen', 'doz', 'darjan', 'darjan'};
  const piece = {'piece', 'pieces', 'pc', 'pcs', 'dana', 'each', 'unit', 'nag'};
  if (kg.contains(t)) return ItemUnit.kg;
  if (pack.contains(t)) return ItemUnit.pack;
  if (dozen.contains(t)) return ItemUnit.dozen;
  if (piece.contains(t)) return ItemUnit.piece;
  return null;
}

class ItemAssessment {
  const ItemAssessment({
    required this.issues,
    required this.unit,
    required this.cost,
    required this.price,
    required this.stock,
    required this.low,
    required this.barcode,
    this.nameKey = '',
  });

  final Set<RowIssue> issues;
  final String unit;
  final int cost;
  final int price;
  final int stock;
  final int low;
  final String? barcode;
  final String nameKey;

  bool get hasError => issues.contains(RowIssue.error);
  bool get isUncertain => issues.contains(RowIssue.uncertain);
  bool get isDuplicate => issues.contains(RowIssue.duplicate);
}

ItemAssessment assessItem(
  ItemImportRow row, {
  required Set<String> existingNames,
  required Set<String> existingBarcodes,
  required Set<String> seenNames,
  required Set<String> seenBarcodes,
}) {
  final issues = <RowIssue>{};
  final name = row.name.trim();
  if (name.isEmpty) issues.add(RowIssue.error);

  var unit = mapUnit(row.unit);
  if (unit == null) {
    unit = ItemUnit.kg;
    if (row.unit.trim().isNotEmpty) issues.add(RowIssue.uncertain);
  }

  int money(String s) {
    final a = parseImportAmount(s);
    if (a.error || a.paisa < 0) issues.add(RowIssue.error);
    if (a.uncertain) issues.add(RowIssue.uncertain);
    return a.error || a.paisa < 0 ? 0 : a.paisa;
  }

  final cost = money(row.cost);
  final price = money(row.price);

  int qty(String s, {bool allowNegative = false}) {
    final q = parseImportQty(s);
    if (q == null || (!allowNegative && q < 0)) {
      issues.add(RowIssue.error);
      return 0;
    }
    return q;
  }

  final stock = qty(row.stock, allowNegative: true);
  final low = qty(row.low);

  final barcode = row.barcode.trim().isEmpty ? null : row.barcode.trim();
  final nameKey = normalizeName(name);
  var duplicate = false;
  if (nameKey.isNotEmpty &&
      (existingNames.contains(nameKey) || seenNames.contains(nameKey))) {
    duplicate = true;
  }
  if (barcode != null &&
      (existingBarcodes.contains(barcode) || seenBarcodes.contains(barcode))) {
    // A repeated barcode cannot be saved at all (barcodes are unique).
    issues.add(RowIssue.error);
    duplicate = true;
  }
  if (duplicate) issues.add(RowIssue.duplicate);

  return ItemAssessment(
    issues: issues,
    unit: unit,
    cost: cost,
    price: price,
    stock: stock,
    low: low,
    barcode: barcode,
    nameKey: nameKey,
  );
}

List<ItemAssessment> assessAllItems(
  List<ItemImportRow> rows, {
  required Set<String> existingNames,
  required Set<String> existingBarcodes,
}) {
  final seenNames = <String>{};
  final seenBarcodes = <String>{};
  final out = <ItemAssessment>[];
  for (final r in rows) {
    final a = assessItem(r,
        existingNames: existingNames,
        existingBarcodes: existingBarcodes,
        seenNames: seenNames,
        seenBarcodes: seenBarcodes);
    if (r.include && !a.hasError) {
      if (a.nameKey.isNotEmpty) seenNames.add(a.nameKey);
      if (a.barcode != null) seenBarcodes.add(a.barcode!);
    }
    out.add(a);
  }
  return out;
}
