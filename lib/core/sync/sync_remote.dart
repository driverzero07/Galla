import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Why a sync step failed (the UI turns this into words, no data inside).
enum SyncFailure { notReady, offline, rejected, server }

class SyncException implements Exception {
  const SyncException(this.failure);
  final SyncFailure failure;
  @override
  String toString() => 'SyncException($failure)';
}

/// The server side of sync, behind an interface so the engine can be tested
/// with an in-memory fake and so Supabase stays in one file.
abstract class SyncRemote {
  /// False when Supabase is not configured or nobody is signed in.
  bool get isReady;

  /// Idempotent upsert by `id`.
  Future<void> upsert(String table, List<Map<String, Object?>> rows);

  /// Rows of [shopId] changed at or after [since] (the server's own
  /// `server_updated_at` text, kept exactly as received), oldest first.
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required String shopId,
    String? since,
    required int limit,
  });

  /// Uploads a photo and returns a long-lived URL for it.
  Future<String> uploadPhoto({required String shopId, required String localPath});
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  bool get isReady {
    if (!Env.supabaseConfigured) return false;
    try {
      return _client.auth.currentSession != null;
    } catch (_) {
      return false; // Supabase.initialize was not called
    }
  }

  Never _fail(Object e) {
    if (e is SocketException || e is HttpException) {
      throw const SyncException(SyncFailure.offline);
    }
    if (e is PostgrestException) {
      final code = int.tryParse(e.code ?? '');
      if (code != null && code >= 400 && code < 500) {
        throw const SyncException(SyncFailure.rejected);
      }
      throw const SyncException(SyncFailure.server);
    }
    if (e is AuthException) throw const SyncException(SyncFailure.notReady);
    throw const SyncException(SyncFailure.offline);
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    try {
      await _client.from(table).upsert(rows, onConflict: 'id');
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required String shopId,
    String? since,
    required int limit,
  }) async {
    try {
      var q = _client.from(table).select().eq('shop_id', shopId);
      if (since != null) q = q.gte('server_updated_at', since);
      final res = await q
          .order('server_updated_at', ascending: true)
          .order('id', ascending: true)
          .limit(limit);
      return [for (final r in res) Map<String, dynamic>.from(r as Map)];
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<String> uploadPhoto(
      {required String shopId, required String localPath}) async {
    try {
      final name = p.basename(localPath);
      final path = '$shopId/$name';
      await _client.storage.from('photos').upload(
            path,
            File(localPath),
            fileOptions: const FileOptions(
                upsert: true, contentType: 'image/jpeg'),
          );
      // The bucket is private; a one-year signed link is stored on the row.
      return await _client.storage
          .from('photos')
          .createSignedUrl(path, 60 * 60 * 24 * 365);
    } catch (e) {
      _fail(e);
    }
  }
}
