import 'dart:convert';

import 'import_rows.dart';

/// One name and balance read from a photo, with how sure the model was.
class OcrEntry {
  const OcrEntry({
    required this.name,
    required this.amount,
    required this.confidence,
  });

  final String name;

  /// As written (may hold a "?").
  final String amount;

  /// 0.0 to 1.0.
  final double confidence;
}

/// Below this the row is shown as "Pakka nahi, check karo".
const ocrConfidenceThreshold = 0.8;

/// Reads the Edge Function reply:
/// `{"entries":[{"name":"Akram","amount":"3400","confidence":0.93}]}`.
/// Anything malformed is skipped; a reply that is not that shape gives [].
List<OcrEntry> parseOcrResponse(Object? body) {
  Object? data = body;
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return const [];
    }
  }
  if (data is! Map) return const [];
  final list = data['entries'];
  if (list is! List) return const [];
  final out = <OcrEntry>[];
  for (final e in list) {
    if (e is! Map) continue;
    final name = e['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final amount = e['amount'];
    final c = e['confidence'];
    out.add(OcrEntry(
      name: name.trim(),
      amount: amount == null ? '' : amount.toString(),
      confidence: c is num ? c.toDouble().clamp(0.0, 1.0) : 0.0,
    ));
  }
  return out;
}

List<PartyImportRow> rowsFromOcr(List<OcrEntry> entries, {int startId = 0}) {
  return [
    for (var i = 0; i < entries.length; i++)
      PartyImportRow(
        id: startId + i,
        name: entries[i].name,
        amount: entries[i].amount,
        sourceUncertain: entries[i].confidence < ocrConfidenceThreshold,
      ),
  ];
}
