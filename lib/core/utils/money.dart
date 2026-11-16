import 'package:intl/intl.dart';

/// Money is stored as integer paisa; quantity as integer thousandths
/// (2.5 kg = 2500). Never use double for either.
///
/// Number grouping is en_IN: 1,84,300.
final NumberFormat _grouping = NumberFormat.decimalPattern('en_IN');

/// Formats [paisa] as `Rs 1,84,300`. Paisa are shown only when non-zero
/// (`Rs 12.34`). Negative values are `-Rs 500`.
String formatPaisa(int paisa, {bool symbol = true}) {
  final negative = paisa < 0;
  final abs = paisa.abs();
  final rupees = abs ~/ 100;
  final fraction = abs % 100;
  var text = _grouping.format(rupees);
  if (fraction != 0) {
    text = '$text.${fraction.toString().padLeft(2, '0')}';
  }
  final sign = negative ? '-' : '';
  return symbol ? '${sign}Rs $text' : '$sign$text';
}

/// Formats quantity thousandths: 2500 -> `2.5`, 2000 -> `2`, 125 -> `0.125`.
String formatQty(int milli) {
  final negative = milli < 0;
  final abs = milli.abs();
  final whole = abs ~/ 1000;
  final fraction = abs % 1000;
  var text = _grouping.format(whole);
  if (fraction != 0) {
    final f = fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
    text = '$text.$f';
  }
  return negative ? '-$text' : text;
}

/// Parses user input like `1,200`, ` 12.5 `, `Rs 300` into paisa.
/// Returns null when [input] is not a valid non-negative amount.
int? parseRupeesToPaisa(String input) => _parseScaled(input, scale: 100);

/// Parses user input like `2.5` into quantity thousandths.
/// Returns null when [input] is not a valid non-negative quantity.
int? parseQtyToMilli(String input) => _parseScaled(input, scale: 1000);

int? _parseScaled(String input, {required int scale}) {
  final cleaned = input
      .replaceAll(RegExp(r'rs\.?', caseSensitive: false), '')
      .replaceAll(RegExp(r'[,\s]'), '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(cleaned);
  if (match == null) return null;
  final digits = scale.toString().length - 1; // 100 -> 2, 1000 -> 3
  final whole = int.parse(match.group(1)!);
  var frac = match.group(2) ?? '';
  if (frac.length > digits) frac = frac.substring(0, digits);
  frac = frac.padRight(digits, '0');
  return whole * scale + (frac.isEmpty ? 0 : int.parse(frac));
}

/// Editable text for an input field: `165`, `12.5`, `12.05`. No grouping.
String formatPaisaPlain(int paisa) {
  final abs = paisa.abs();
  final rupees = abs ~/ 100;
  final fraction = abs % 100;
  if (fraction == 0) return '$rupees';
  final f = fraction.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '');
  return '$rupees.$f';
}

/// Editable text for a quantity field: `2.5`, `50`. No grouping.
String formatQtyPlain(int milli) {
  final abs = milli.abs();
  final whole = abs ~/ 1000;
  final fraction = abs % 1000;
  final sign = milli < 0 ? '-' : '';
  if (fraction == 0) return '$sign$whole';
  final f = fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
  return '$sign$whole.$f';
}
