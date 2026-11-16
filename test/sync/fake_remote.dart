import 'package:galla/core/sync/sync_remote.dart';
import 'package:path/path.dart' as p;

/// In-memory stand-in for Supabase: upserts by id and stamps every write
/// with an increasing `server_updated_at`, like the real trigger does.
class FakeRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  final List<({String table, int rows})> upserts = [];
  final List<String> uploaded = [];
  bool ready = true;

  /// 0-based index of the upsert call that throws (-1 = never).
  int failUpsertAt = -1;
  int _calls = 0;
  int _clock = 0;

  String _stamp() => DateTime.utc(2026, 1, 1)
      .add(Duration(milliseconds: ++_clock))
      .toIso8601String();

  @override
  bool get isReady => ready;

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    final call = _calls++;
    if (call == failUpsertAt) throw const SyncException(SyncFailure.offline);
    upserts.add((table: table, rows: rows.length));
    final t = tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      t[r['id'] as String] = {...r, 'server_updated_at': _stamp()};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required String shopId,
    String? since,
    required int limit,
  }) async {
    final rows = (tables[table]?.values ?? const <Map<String, dynamic>>[])
        .where((r) => r['shop_id'] == shopId)
        .where((r) =>
            since == null ||
            (r['server_updated_at'] as String).compareTo(since) >= 0)
        .toList()
      ..sort((a, b) {
        final c = (a['server_updated_at'] as String)
            .compareTo(b['server_updated_at'] as String);
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    return [for (final r in rows.take(limit)) Map<String, dynamic>.from(r)];
  }

  @override
  Future<String> uploadPhoto(
      {required String shopId, required String localPath}) async {
    uploaded.add(localPath);
    return 'https://fake.example/$shopId/${p.basename(localPath)}';
  }

  int count(String table) => tables[table]?.length ?? 0;
}
