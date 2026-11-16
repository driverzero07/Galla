/// Digits and separators from Urdu / Arabic keyboards and spreadsheets.
String normalizeDigits(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + (r - 0x06F0)); // Extended Arabic-Indic
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + (r - 0x0660)); // Arabic-Indic
    } else if (r == 0x066B) {
      b.write('.'); // Arabic decimal separator
    } else if (r == 0x066C || r == 0x060C) {
      b.write(','); // Arabic thousands separator / comma
    } else if (r == 0x00A0 || r == 0x200B || r == 0x200E || r == 0x200F ||
        r == 0x202F || r == 0xFEFF) {
      b.write(' '); // no-break and invisible spaces
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// Result of reading an amount typed or imported from paper / a sheet.
class ImportAmount {
  const ImportAmount({
    this.paisa = 0,
    this.uncertain = false,
    this.error = false,
  });

  /// Signed paisa. 0 when empty or unreadable.
  final int paisa;

  /// Readable but worth a second look (a "?", odd commas, extra decimals).
  final bool uncertain;

  /// Not a number at all.
  final bool error;
}

final _currencyWords = RegExp(
  r'(pkr|rupees?|rs\.?|\u0631\u0648\u067E\u06D2)',
  caseSensitive: false,
);

/// Reads "1,200", "Rs 1,20,000", "1200.50", "\u06F1\u06F2\u06F0\u06F0", " 860 ? ", "-500",
/// "(500)" into paisa without floating point. Empty means 0.
ImportAmount parseImportAmount(String raw) {
  var t = normalizeDigits(raw).trim();
  if (t.isEmpty) return const ImportAmount();

  var uncertain = false;
  if (t.contains('?') || t.contains('\u061F')) {
    uncertain = true;
    t = t.replaceAll('?', '').replaceAll('\u061F', '');
  }
  t = t.replaceAll(_currencyWords, '').replaceAll('/-', '').trim();

  var negative = false;
  if (t.startsWith('(') && t.endsWith(')')) {
    negative = true;
    t = t.substring(1, t.length - 1).trim();
  }
  if (t.startsWith('-') || t.startsWith('\u2212')) {
    negative = true;
    t = t.substring(1).trim();
  } else if (t.startsWith('+')) {
    t = t.substring(1).trim();
  }
  t = t.replaceAll(' ', '');
  if (t.isEmpty) return ImportAmount(uncertain: uncertain, error: true);

  // Thousands commas. Western (1,200,000) and Indian (12,00,000) grouping
  // are both fine; anything else is readable but suspicious.
  if (t.contains(',')) {
    final whole = t.split('.').first;
    final good = RegExp(r'^\d{1,3}(,\d{2,3})*(,\d{3})$').hasMatch(whole) ||
        RegExp(r'^\d{1,3},\d{3}$').hasMatch(whole);
    if (!good) uncertain = true;
    t = t.replaceAll(',', '');
  }

  final m = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(t);
  if (m == null) return ImportAmount(uncertain: uncertain, error: true);

  final rupees = m.group(1)!;
  if (rupees.length > 9) return ImportAmount(uncertain: uncertain, error: true);
  var frac = m.group(2) ?? '';
  var carry = 0;
  if (frac.length > 2) {
    uncertain = true;
    // Round half up on the third digit.
    carry = frac.codeUnitAt(2) >= 0x35 ? 1 : 0;
    frac = frac.substring(0, 2);
  }
  final paisaPart = int.parse(frac.padRight(2, '0'));
  var paisa = int.parse(rupees) * 100 + paisaPart + carry;
  if (negative) paisa = -paisa;
  return ImportAmount(paisa: paisa, uncertain: uncertain);
}

/// Quantity in thousandths ("2.5" -> 2500). Null if not a number. Empty is 0.
int? parseImportQty(String raw) {
  var t = normalizeDigits(raw).trim().replaceAll(' ', '');
  if (t.isEmpty) return 0;
  t = t.replaceAll(',', '');
  final m = RegExp(r'^(-?\d+)(?:\.(\d*))?$').firstMatch(t);
  if (m == null) return null;
  final whole = m.group(1)!;
  if (whole.replaceAll('-', '').length > 9) return null;
  var frac = (m.group(2) ?? '');
  var carry = 0;
  if (frac.length > 3) {
    carry = frac.codeUnitAt(3) >= 0x35 ? 1 : 0;
    frac = frac.substring(0, 3);
  }
  final neg = whole.startsWith('-');
  final w = int.parse(whole.replaceAll('-', ''));
  final v = w * 1000 + int.parse(frac.padRight(3, '0')) + carry;
  return neg ? -v : v;
}
