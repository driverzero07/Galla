/// Normalises a Pakistani mobile number to E.164 (`+923001234567`).
/// Accepts `0300 1234567`, `0300-1234567`, `923001234567`, `+92 300 1234567`.
/// Returns null if it does not look like a valid number.
String? normalizePkPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.startsWith('+')) digits = digits.substring(1);
  if (digits.startsWith('0092')) digits = digits.substring(4);
  if (digits.startsWith('92')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (!RegExp(r'^3\d{9}$').hasMatch(digits)) return null;
  return '+92$digits';
}

/// `+923001234567` -> `0300 1234567`.
String displayPkPhone(String e164) {
  if (!RegExp(r'^\+923\d{9}$').hasMatch(e164)) return e164;
  final local = '0${e164.substring(3)}';
  return '${local.substring(0, 4)} ${local.substring(4)}';
}
