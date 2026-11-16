import 'dart:convert';
import 'dart:typed_data';

/// Turns file bytes into text. Handles UTF-8 (with or without BOM) and the
/// UTF-16 that some Excel "Unicode text" exports use, so Urdu names survive.
String decodeTableBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, 2, Endian.little);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, 2, Endian.big);
  }
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  return utf8.decode(bytes.sublist(start), allowMalformed: true);
}

String _utf16(Uint8List b, int start, Endian e) {
  final data = ByteData.sublistView(b);
  final units = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    units.add(data.getUint16(i, e));
  }
  return String.fromCharCodes(units);
}

/// Picks the separator (comma, semicolon, tab or pipe) used by the first
/// non-empty line, ignoring separators inside quotes.
String detectDelimiter(String text) {
  const candidates = [',', ';', '\t', '|'];
  final counts = {for (final c in candidates) c: 0};
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (!inQuotes) {
      if (ch == '\n') {
        if (counts.values.any((v) => v > 0)) break;
      } else if (counts.containsKey(ch)) {
        counts[ch] = counts[ch]! + 1;
      }
    }
  }
  var best = ',';
  var bestCount = 0;
  for (final c in candidates) {
    if (counts[c]! > bestCount) {
      best = c;
      bestCount = counts[c]!;
    }
  }
  return best;
}

/// RFC 4180 style parser: quoted fields, "" escapes, newlines inside quotes,
/// CRLF or LF. Fields are trimmed; rows with only empty cells are dropped.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final d = delimiter ?? detectDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var wasQuoted = false;

  void endField() {
    row.add(field.toString().trim());
    field.clear();
    wasQuoted = false;
  }

  void endRow() {
    endField();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
      wasQuoted = true;
    } else if (ch == d) {
      endField();
    } else if (ch == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else if (ch == '\n') {
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty || wasQuoted) endRow();
  return rows;
}
