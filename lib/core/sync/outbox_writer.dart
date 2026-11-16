import 'dart:convert';

import '../db/app_database.dart';
import '../db/constants.dart';

/// Collects the rows changed inside a [writeWithOutbox] transaction.
class OutboxBatch {
  final List<_PendingEntry> _entries = [];

  /// Record that [rowId] of [table] changed. [payload] is the full row as
  /// JSON-encodable data, normally `row.toJson()` from a Drift data class.
  void record({
    required String table,
    required String rowId,
    required Map<String, Object?> payload,
    String op = OutboxOp.update,
  }) {
    _entries.add(_PendingEntry(table, rowId, op, jsonEncode(payload)));
  }

  int get length => _entries.length;
}

class _PendingEntry {
  _PendingEntry(this.table, this.rowId, this.op, this.payload);
  final String table;
  final String rowId;
  final String op;
  final String payload;
}

/// Runs [body] in ONE database transaction and writes every row it recorded
/// into the outbox in the same transaction, so a change is never saved
/// without being queued for sync (and never queued without being saved).
/// The UI never waits for the network.
///
/// ```dart
/// await writeWithOutbox(db, (outbox) async {
///   final row = await db.into(db.items).insertReturning(companion);
///   outbox.record(table: 'items', rowId: row.id,
///       payload: row.toJson(), op: OutboxOp.insert);
/// });
/// ```
Future<T> writeWithOutbox<T>(
  AppDatabase db,
  Future<T> Function(OutboxBatch outbox) body, {
  DateTime Function()? now,
}) {
  return db.transaction(() async {
    final batch = OutboxBatch();
    final result = await body(batch);
    final stamp = (now ?? DateTime.now)();
    for (final e in batch._entries) {
      await db.outboxDao.enqueue(
        table: e.table,
        rowId: e.rowId,
        op: e.op,
        payload: e.payload,
        now: stamp,
      );
    }
    return result;
  });
}
