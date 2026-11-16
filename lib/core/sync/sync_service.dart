import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';
import '../db/app_database.dart';
import '../db/db_providers.dart';
import 'connectivity.dart';
import 'outbox_writer.dart';
import 'sync_mapping.dart';
import 'sync_remote.dart';
import 'sync_status.dart';

/// What the Settings screen shows. Never contains customer data.
class SyncState {
  const SyncState({
    this.running = false,
    this.lastSuccessAt,
    this.failure,
    this.failures = 0,
    this.stuck = 0,
  });

  final bool running;
  final DateTime? lastSuccessAt;

  /// Why the last run failed; null after a success.
  final SyncFailure? failure;
  final int failures;

  /// Outbox entries the server keeps refusing.
  final int stuck;

  SyncState copyWith({
    bool? running,
    DateTime? lastSuccessAt,
    SyncFailure? failure,
    bool clearFailure = false,
    int? failures,
    int? stuck,
  }) =>
      SyncState(
        running: running ?? this.running,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        failure: clearFailure ? null : (failure ?? this.failure),
        failures: failures ?? this.failures,
        stuck: stuck ?? this.stuck,
      );
}

/// Wait before the next automatic try: 5 s, 10 s, 20 s ... at most 15 min.
Duration syncBackoff(int failures) {
  if (failures <= 0) return Duration.zero;
  final seconds = 5 * (1 << (failures - 1).clamp(0, 10));
  return Duration(seconds: seconds > 900 ? 900 : seconds);
}

/// Real sync (Part 7). Order of one run: photos, push, pull.
///  * Push: the outbox oldest first, 50 rows per batch, idempotent upserts by
///    UUID. An outbox entry is deleted only AFTER the server confirmed it.
///  * Pull: per table, rows changed since that table's cursor, applied in
///    dependency order. Rows with an unsent local change are skipped, so the
///    latest write (local or server arrival) wins.
///  * Failures back off exponentially; "Sync abhi" ignores the wait.
class SyncService {
  SyncService(
    this._db,
    this._remote,
    this._shopId, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final SyncRemote _remote;
  final String? Function() _shopId;
  final DateTime Function() _now;

  static const interval = Duration(minutes: 5);
  static const batchSize = 50;
  static const pullPageSize = 500;
  static const lastSyncKey = 'last_sync_ms';
  static String cursorKey(String table) => 'sync_cursor_$table';

  bool _running = false;
  int _failures = 0;
  DateTime? _nextAttempt;
  SyncState _state = const SyncState();
  final _controller = StreamController<SyncState>.broadcast();

  SyncState get state => _state;
  Stream<SyncState> get states => _controller.stream;

  void _emit(SyncState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void dispose() => _controller.close();

  /// Safe to call from anywhere; overlapping runs are ignored. [force] (the
  /// manual button) skips the backoff wait. Returns true on success.
  Future<bool> syncNow({required String reason, bool force = false}) async {
    if (_running) return false;
    final shopId = _shopId();
    if (shopId == null) return false;
    if (!_remote.isReady) {
      _emit(_state.copyWith(failure: SyncFailure.notReady));
      return false;
    }
    final wait = _nextAttempt;
    if (!force && wait != null && _now().isBefore(wait)) return false;

    _running = true;
    _emit(_state.copyWith(running: true));
    try {
      dev.log('sync start ($reason)', name: 'galla.sync');
      await uploadPhotos(shopId);
      await pushOutbox();
      await pullChanges(shopId);
      final stamp = _now();
      await _db.deviceStateDao.set(lastSyncKey, '${stamp.millisecondsSinceEpoch}');
      _failures = 0;
      _nextAttempt = null;
      _emit(SyncState(
        lastSuccessAt: stamp,
        stuck: await _db.outboxDao.stuckCount(),
      ));
      return true;
    } on SyncException catch (e) {
      await _fail(e.failure);
      return false;
    } catch (e) {
      // Never log the exception text: it could contain customer data.
      dev.log('sync failed (${e.runtimeType})', name: 'galla.sync');
      await _fail(SyncFailure.server);
      return false;
    } finally {
      _running = false;
    }
  }

  Future<void> _fail(SyncFailure failure) async {
    _failures++;
    _nextAttempt = _now().add(syncBackoff(_failures));
    final stuck = await _db.outboxDao.stuckCount();
    _emit(_state.copyWith(
        running: false, failure: failure, failures: _failures, stuck: stuck));
  }

  Future<DateTime?> lastSyncAt() async {
    final v = int.tryParse(await _db.deviceStateDao.get(lastSyncKey) ?? '');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  // -------------------------------------------------------------- push

  Future<void> pushOutbox() async {
    while (true) {
      final batch = await _db.outboxDao.nextBatch(limit: batchSize);
      if (batch.isEmpty) return;
      await _pushBatch(batch);
    }
  }

  Future<void> _pushBatch(List<OutboxEntry> batch) async {
    // One request per table (tables in the order they first appear). The
    // server has no foreign keys, so rows of different tables may arrive in
    // any order. One row can appear twice (insert, then update): the newest
    // payload wins. Entries are deleted only after the server confirmed.
    final byTable = <String, List<OutboxEntry>>{};
    for (final e in batch) {
      byTable.putIfAbsent(e.entityTable, () => []).add(e);
    }
    for (final MapEntry(key: table, value: entries) in byTable.entries) {
      final rows = <String, Map<String, Object?>>{};
      for (final e in entries) {
        rows[e.rowId] =
            toServerRow(jsonDecode(e.payload) as Map<String, Object?>);
      }
      try {
        await _remote.upsert(table, rows.values.toList());
      } catch (_) {
        await _db.outboxDao.bumpAttempts(entries.map((e) => e.id));
        rethrow;
      }
      await _db.outboxDao.markDone(entries.map((e) => e.id));
    }
  }

  // ------------------------------------------------------------ photos

  /// Uploads photos taken on this phone that have no remote URL yet. The row
  /// keeps both the local path and the URL, and the change is queued.
  Future<void> uploadPhotos(String shopId) async {
    final items = await (_db.select(_db.items)
          ..where((t) => t.photoPath.isNotNull() & t.photoUrl.isNull()))
        .get();
    for (final item in items) {
      final path = item.photoPath!;
      if (!await File(path).exists()) continue;
      final url = await _remote.uploadPhoto(shopId: shopId, localPath: path);
      await writeWithOutbox(_db, (outbox) async {
        await (_db.update(_db.items)..where((t) => t.id.equals(item.id)))
            .write(ItemsCompanion(
                photoUrl: Value(url), updatedAt: Value(_now())));
        final row = await _db.inventoryDao.itemById(item.id);
        if (row != null) {
          outbox.record(table: 'items', rowId: row.id, payload: row.toJson());
        }
      }, now: _now);
    }

    final purchases = await (_db.select(_db.purchases)
          ..where((t) =>
              t.invoiceImagePath.isNotNull() & t.invoiceImageUrl.isNull()))
        .get();
    for (final pu in purchases) {
      final path = pu.invoiceImagePath!;
      if (!await File(path).exists()) continue;
      final url = await _remote.uploadPhoto(shopId: shopId, localPath: path);
      await writeWithOutbox(_db, (outbox) async {
        await (_db.update(_db.purchases)..where((t) => t.id.equals(pu.id)))
            .write(PurchasesCompanion(
                invoiceImageUrl: Value(url), updatedAt: Value(_now())));
        final row = await (_db.select(_db.purchases)
              ..where((t) => t.id.equals(pu.id)))
            .getSingleOrNull();
        if (row != null) {
          outbox.record(
              table: 'purchases', rowId: row.id, payload: row.toJson());
        }
      }, now: _now);
    }
  }

  // -------------------------------------------------------------- pull

  /// Pulls every table (in dependency order). [includeSettings] is used by
  /// restore on a new phone. Returns how many rows were applied.
  Future<int> pullChanges(String shopId, {bool includeSettings = false}) async {
    var applied = 0;
    final tables = [
      ...syncTables,
      if (includeSettings) ...restoreOnlyTables,
    ];
    for (final table in tables) {
      applied += await _pullTable(table, shopId);
    }
    return applied;
  }

  Future<int> _pullTable(String table, String shopId) async {
    var applied = 0;
    var cursor = await _db.deviceStateDao.get(cursorKey(table));
    while (true) {
      final page = await _remote.fetchChanged(
        table,
        shopId: shopId,
        since: cursor,
        limit: pullPageSize,
      );
      if (page.isEmpty) break;

      final pending = await _db.outboxDao.pendingRowIds(table);
      await _db.transaction(() async {
        for (final row in page) {
          if (pending.contains(row['id'])) continue; // local change is newer
          await applyServerRow(_db, table, row);
          applied++;
        }
      });

      final last = page.last['server_updated_at'] as String?;
      if (last == null) break;
      final moved = last != cursor;
      cursor = last;
      await _db.deviceStateDao.set(cursorKey(table), last);
      // Rows at the cursor are fetched again next time ("at or after"); that
      // is harmless because applying is an idempotent upsert.
      if (page.length < pullPageSize || !moved) break;
    }
    return applied;
  }
}

final syncRemoteProvider = Provider<SyncRemote>((ref) => SupabaseSyncRemote());

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(syncRemoteProvider),
    () {
      final auth = ref.read(authControllerProvider);
      return auth is AuthUnlocked ? auth.shopId : null;
    },
    now: ref.watch(clockProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Live sync state for the Settings screen.
final syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final service = ref.watch(syncServiceProvider);
  yield service.state;
  yield* service.states;
});

/// Triggers sync on reconnect, after unlock, a few seconds after new changes
/// are queued while online, and every 5 minutes. App-resume is triggered from
/// the lifecycle observer in app.dart. Watch this once near the root.
final syncWorkerProvider = Provider<void>((ref) {
  final service = ref.watch(syncServiceProvider);

  ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
    final wasOnline = previous?.valueOrNull ?? false;
    final isOnline = next.valueOrNull ?? false;
    if (isOnline && !wasOnline) service.syncNow(reason: 'reconnect');
  });

  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    if (next is AuthUnlocked && previous is! AuthUnlocked) {
      service.syncNow(reason: 'unlock');
    }
  });

  // A bill saved while online goes up within a few seconds (debounced).
  Timer? debounce;
  ref.listen<AsyncValue<int>>(pendingChangesProvider, (previous, next) {
    final pending = next.valueOrNull ?? 0;
    final before = previous?.valueOrNull ?? 0;
    if (pending > before) {
      debounce?.cancel();
      debounce = Timer(const Duration(seconds: 8), () {
        service.syncNow(reason: 'change');
      });
    }
  });
  ref.onDispose(() => debounce?.cancel());

  final timer = Timer.periodic(SyncService.interval, (_) {
    service.syncNow(reason: 'timer');
  });
  ref.onDispose(timer.cancel);
});
