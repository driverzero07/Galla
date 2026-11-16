import '../../../core/db/constants.dart';
import 'import_numbers.dart';
import 'import_rows.dart';

/// A column the importer knows how to read.
enum ImportField { name, phone, balance, unit, cost, price, stock, low, barcode }

/// Fields offered for a kind of import; the first one is required.
List<ImportField> fieldsFor(String kind) => kind == ImportKind.items
    ? const [
        ImportField.name,
        ImportField.unit,
        ImportField.cost,
        ImportField.price,
        ImportField.stock,
        ImportField.low,
        ImportField.barcode,
      ]
    : const [ImportField.name, ImportField.phone, ImportField.balance];

/// Header words (lower case) that point at each field, English and Roman
/// Urdu. Urdu script headers are matched too.
const _keywords = <ImportField, List<String>>{
  ImportField.name: [
    'name', 'naam', 'customer', 'party', 'supplier', 'item', 'saman',
    'product', 'description', 'person', 'client', 'account',
    'نام', 'اسم'
  ],
  ImportField.phone: [
    'phone', 'mobile', 'contact', 'cell', 'number', 'whatsapp', 'tel',
    'fon', 'فون', 'موبائل'
  ],
  ImportField.balance: [
    'balance', 'baqaya', 'baqi', 'baqay', 'amount', 'udhaar', 'udhar',
    'due', 'outstanding', 'receivable', 'payable', 'dena', 'lena', 'opening',
    'بقایا', 'باقی',
    'رقم', 'ادھار'
  ],
  ImportField.unit: ['unit', 'uom', 'measure', 'wazan', 'یونٹ'],
  ImportField.cost: [
    'cost', 'purchase', 'kharid', 'buy', 'buying', 'cp', 'wholesale'
  ],
  ImportField.price: [
    'price', 'sale', 'sell', 'selling', 'rate', 'bechna', 'retail', 'sp',
    'mrp', 'قیمت'
  ],
  ImportField.stock: [
    'stock', 'qty', 'quantity', 'bacha', 'available', 'on hand', 'onhand',
    'opening stock', 'balance qty', 'مقدار'
  ],
  ImportField.low: [
    'low', 'min', 'minimum', 'reorder', 'alert', 'khatam', 'threshold'
  ],
  ImportField.barcode: ['barcode', 'bar code', 'sku', 'ean', 'upc', 'code'],
};

/// Which column (0-based) feeds each field. Missing = not mapped.
typedef ColumnMapping = Map<ImportField, int>;

String _norm(String s) => normalizeName(s).replaceAll(RegExp(r'[_\-./]'), ' ');

/// Score of a header cell against a field: exact word beats "contains".
int _score(String header, ImportField f) {
  final h = _norm(header);
  if (h.isEmpty) return 0;
  var best = 0;
  for (final k in _keywords[f]!) {
    if (h == k) {
      best = best < 3 ? 3 : best;
    } else if (h.split(' ').contains(k)) {
      best = best < 2 ? 2 : best;
    } else if (k.length > 3 && h.contains(k)) {
      best = best < 1 ? 1 : best;
    }
  }
  return best;
}

/// True when the first row looks like column titles rather than data: it
/// matches at least one known header word and contains no amount-like cell
/// in a column that has data below.
bool looksLikeHeader(List<List<String>> table, String kind) {
  if (table.isEmpty) return false;
  final first = table.first;
  // A digit in the first line means it is a person / item, not a title.
  if (first.any((c) => RegExp(r'\d').hasMatch(normalizeDigits(c)))) {
    return false;
  }
  var hits = 0;
  for (final cell in first) {
    for (final f in fieldsFor(kind)) {
      if (_score(cell, f) > 0) {
        hits++;
        break;
      }
    }
  }
  return hits > 0;
}

/// Best guess of the mapping from the header row. Each column is used for at
/// most one field. Without a header, falls back to column order
/// (name, phone, balance) for people.
ColumnMapping guessMapping(List<List<String>> table, String kind,
    {required bool hasHeader}) {
  final fields = fieldsFor(kind);
  final mapping = <ImportField, int>{};
  if (table.isEmpty) return mapping;
  final width = table.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  if (hasHeader) {
    final header = table.first;
    final used = <int>{};
    // Highest scores first so "Name" is not stolen by a weaker match.
    final candidates = <({ImportField f, int col, int score})>[];
    for (final f in fields) {
      for (var c = 0; c < header.length; c++) {
        final s = _score(header[c], f);
        if (s > 0) candidates.add((f: f, col: c, score: s));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    for (final c in candidates) {
      if (mapping.containsKey(c.f) || used.contains(c.col)) continue;
      mapping[c.f] = c.col;
      used.add(c.col);
    }
    return mapping;
  }

  // No header: people are name, phone, balance; items are name, unit, cost,
  // price, stock.
  final order = kind == ImportKind.items
      ? fields
      : const [ImportField.name, ImportField.phone, ImportField.balance];
  if (kind != ImportKind.items && width == 2) {
    // name + balance
    mapping[ImportField.name] = 0;
    mapping[ImportField.balance] = 1;
    return mapping;
  }
  for (var i = 0; i < order.length && i < width; i++) {
    mapping[order[i]] = i;
  }
  return mapping;
}

String _cell(List<String> row, ColumnMapping m, ImportField f) {
  final i = m[f];
  if (i == null || i < 0 || i >= row.length) return '';
  return row[i].trim();
}

/// Builds party rows from a table. Blank rows are skipped.
List<PartyImportRow> partyRowsFromTable(
  List<List<String>> table,
  ColumnMapping mapping, {
  required bool hasHeader,
  int startId = 0,
}) {
  final out = <PartyImportRow>[];
  var id = startId;
  for (var i = hasHeader ? 1 : 0; i < table.length; i++) {
    final r = table[i];
    final row = PartyImportRow(
      id: id,
      name: _cell(r, mapping, ImportField.name),
      phone: _cell(r, mapping, ImportField.phone),
      amount: _cell(r, mapping, ImportField.balance),
    );
    if (row.isBlank) continue;
    out.add(row);
    id++;
  }
  return out;
}

/// Builds item rows from a table. Blank rows are skipped.
List<ItemImportRow> itemRowsFromTable(
  List<List<String>> table,
  ColumnMapping mapping, {
  required bool hasHeader,
  int startId = 0,
}) {
  final out = <ItemImportRow>[];
  var id = startId;
  for (var i = hasHeader ? 1 : 0; i < table.length; i++) {
    final r = table[i];
    final row = ItemImportRow(
      id: id,
      name: _cell(r, mapping, ImportField.name),
      unit: _cell(r, mapping, ImportField.unit),
      cost: _cell(r, mapping, ImportField.cost),
      price: _cell(r, mapping, ImportField.price),
      stock: _cell(r, mapping, ImportField.stock),
      low: _cell(r, mapping, ImportField.low),
      barcode: _cell(r, mapping, ImportField.barcode),
    );
    final blank = row.name.isEmpty &&
        row.unit.isEmpty &&
        row.cost.isEmpty &&
        row.price.isEmpty &&
        row.stock.isEmpty &&
        row.barcode.isEmpty;
    if (blank) continue;
    out.add(row);
    id++;
  }
  return out;
}
