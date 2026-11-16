import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../sync/sync_status.dart';
import 'galla_chip.dart';

/// Shows one of three states: Sab save hai / Net nahi data save ho raha hai /
/// N changes bheje jane baqi.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(syncStatusProvider);
    return switch (status) {
      SyncAllSaved() => GallaChip(
          label: l10n.syncAllSaved,
          icon: Icons.check_circle_outline,
        ),
      SyncOffline() => GallaChip(
          label: l10n.syncOffline,
          icon: Icons.cloud_off_outlined,
          tone: GallaChipTone.warning,
        ),
      SyncPending(:final count) => GallaChip(
          label: l10n.syncPending(count),
          icon: Icons.sync,
          tone: GallaChipTone.warning,
        ),
    };
  }
}
