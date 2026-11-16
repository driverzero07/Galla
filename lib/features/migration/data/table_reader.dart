import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../domain/csv_parser.dart';

/// Thrown when a file cannot be read as a table.
class TableReadException implements Exception {
  const TableReadException(this.reason);

  /// 'unsupported' (.xls, .pdf...) or 'empty' or 'broken'.
  final String reason;
  @override
  String toString() => 'TableReadException($reason)';
}

/// A cell as text. Whole numbers lose the ".0" a spreadsheet adds.
String cellToText(Object? v) {
  if (v == null) return '';
  if (v is double) {
    if (v == v.truncateToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }
  return v.toString().trim();
}

/// Reads a CSV / text file or an .xlsx workbook (first sheet with data).
/// Old .xls files are not supported; the owner saves them as .xlsx or .csv.
List<List<String>> readTable(Uint8List bytes, String fileName) {
  final name = fileName.toLowerCase();
  List<List<String>> rows;
  try {
    if (name.endsWith('.xlsx') || name.endsWith('.ods')) {
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      rows = [];
      for (final table in decoder.tables.values) {
        final candidate = [
          for (final r in table.rows) [for (final c in r) cellToText(c)],
        ].where((r) => r.any((c) => c.isNotEmpty)).toList();
        if (candidate.isNotEmpty) {
          rows = candidate;
          break;
        }
      }
    } else if (name.endsWith('.csv') || name.endsWith('.txt') ||
        name.endsWith('.tsv')) {
      rows = parseCsv(decodeTableBytes(bytes));
    } else {
      throw const TableReadException('unsupported');
    }
  } on TableReadException {
    rethrow;
  } catch (_) {
    throw const TableReadException('broken');
  }
  if (rows.isEmpty) throw const TableReadException('empty');
  // Make every row as wide as the widest so column picking is safe.
  final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  return [
    for (final r in rows) [...r, ...List.filled(width - r.length, '')],
  ];
}
