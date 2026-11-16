import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  Future<int> enqueue({
    required String table,
    required String rowId,
    required String op,
    required String payload,
    required DateTime now,
  }) {
    return into(outbox).insert(OutboxCompanion.insert(
      entityTable: table,
      rowId: rowId,
      op: op,
      payload: payload,
      createdAt: now,
    ));
  }

  /// Oldest first, so the server applies changes in the order they happened.
  Future<List<OutboxEntry>> nextBatch({int limit = 50}) {
    return (select(outbox)
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(limit))
        .get();
  }

  Future<void> markDone(Iterable<int> ids) {
    return (delete(outbox)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> bumpAttempts(Iterable<int> ids) {
    return customUpdate(
      'UPDATE outbox SET attempts = attempts + 1 '
      'WHERE id IN (${ids.map((_) => '?').join(',')})',
      variables: [for (final id in ids) Variable.withInt(id)],
      updates: {outbox},
    );
  }

  /// Ids of rows of [table] that still have an unsent change. A pulled server
  /// copy must not overwrite those (the local change is newer).
  Future<Set<String>> pendingRowIds(String table) async {
    final rows = await (select(outbox)
          ..where((t) => t.entityTable.equals(table)))
        .get();
    return {for (final r in rows) r.rowId};
  }

  /// Entries that failed several times (shown as a sync problem).
  Future<int> stuckCount({int minAttempts = 5}) async {
    final count = outbox.id.count();
    final row = await (selectOnly(outbox)
          ..addColumns([count])
          ..where(outbox.attempts.isBiggerOrEqualValue(minAttempts)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> pendingCount() async {
    final count = outbox.id.count();
    final row = await (selectOnly(outbox)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Stream<int> watchPendingCount() {
    final count = outbox.id.count();
    return (selectOnly(outbox)..addColumns([count]))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }
}
