import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db_providers.dart';
import 'connectivity.dart';

/// The three states of the sync chip.
sealed class SyncStatus {
  const SyncStatus();
}

/// "Sab save hai": nothing waiting to be sent.
class SyncAllSaved extends SyncStatus {
  const SyncAllSaved();
}

/// "Net nahi, data save ho raha hai": offline; changes are safe on the phone.
class SyncOffline extends SyncStatus {
  const SyncOffline();
}

/// "N changes bheje jane baqi": online, N changes still to be pushed.
class SyncPending extends SyncStatus {
  const SyncPending(this.count);
  final int count;
}

/// Pure function so it can be unit tested.
SyncStatus deriveSyncStatus({required bool online, required int pending}) {
  if (!online) return const SyncOffline();
  if (pending > 0) return SyncPending(pending);
  return const SyncAllSaved();
}

final pendingChangesProvider = StreamProvider<int>((ref) {
  return ref.watch(appDatabaseProvider).outboxDao.watchPendingCount();
});

final syncStatusProvider = Provider<SyncStatus>((ref) {
  final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
  final pending = ref.watch(pendingChangesProvider).valueOrNull ?? 0;
  return deriveSyncStatus(online: online, pending: pending);
});
