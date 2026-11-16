import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/sync_remote.dart';
import '../../../core/sync/sync_service.dart';

/// Logging in on a NEW phone: if the server already has this shop, pull
/// everything (the server copy is the backup) before asking for a PIN.
class RestoreService {
  RestoreService(this._db, this._remote);

  final AppDatabase _db;
  final SyncRemote _remote;

  /// True when an existing shop was found and restored. False when the
  /// server has no shop for this account (a real first-time setup) or sync is
  /// not configured. Throws [SyncException] if the network fails half way;
  /// pulling resumes where it stopped on the next try.
  Future<bool> restoreIfExists(String shopId) async {
    if (!_remote.isReady) return false;
    final shops = await _remote.fetchChanged('shops', shopId: shopId, limit: 1);
    if (shops.isEmpty) return false;
    final service = SyncService(_db, _remote, () => shopId);
    try {
      await service.pullChanges(shopId, includeSettings: true);
    } finally {
      service.dispose();
    }
    return true;
  }
}

final restoreServiceProvider = Provider<RestoreService>((ref) => RestoreService(
      ref.watch(appDatabaseProvider),
      ref.watch(syncRemoteProvider),
    ));
