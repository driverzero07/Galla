/// A text cell that a spreadsheet could read as a formula starts with one of
/// these; a leading apostrophe keeps it plain text ("CSV injection").
String safeCell(String s) {
  if (s.isEmpty) return s;
  const risky = {'=', '+', '-', '@', '\t', '\r'};
  return risky.contains(s[0]) ? "'$s" : s;
}

String _quote(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// RFC 4180 CSV. Cells are used as given: pass text through [safeCell]
/// first, numbers as they are.
String toCsv(List<List<String>> rows) =>
    '${rows.map((r) => r.map(_quote).join(',')).join('\r\n')}\r\n';

/// 340000 -> "3400.00" (always two decimals, exact integer maths).
String rupeesCell(int paisa) {
  final abs = paisa.abs();
  final s = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  return paisa < 0 ? '-$s' : s;
}

/// 2500 -> "2.5", 25000 -> "25" (thousandths).
String qtyCell(int milli) {
  final abs = milli.abs();
  final whole = abs ~/ 1000;
  final frac = (abs % 1000).toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
  final s = frac.isEmpty ? '$whole' : '$whole.$frac';
  return milli < 0 ? '-$s' : s;
}
