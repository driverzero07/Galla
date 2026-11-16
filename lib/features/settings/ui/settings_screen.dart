import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_info.dart';
import '../../../core/sync/sync_remote.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/backup_service.dart';

final _lastSyncProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final state = ref.watch(syncStateProvider).valueOrNull;
  if (state?.lastSuccessAt != null) return state!.lastSuccessAt;
  return ref.read(syncServiceProvider).lastSyncAt();
});

/// Sync ka haal, "Sync abhi", CSV backup.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;

  String _failureText(AppLocalizations l10n, SyncFailure f) => switch (f) {
        SyncFailure.notReady => l10n.syncErrNotReady,
        SyncFailure.offline => l10n.syncErrOffline,
        SyncFailure.rejected => l10n.syncErrRejected,
        SyncFailure.server => l10n.syncErrServer,
      };

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(syncServiceProvider)
        .syncNow(reason: 'manual', force: true);
    if (!mounted) return;
    if (ok) messenger.showSnackBar(SnackBar(content: Text(l10n.syncDone)));
  }

  Future<void> _backup() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      await ref.read(backupServiceProvider).exportAndShare();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupFailed)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(syncStateProvider).valueOrNull ?? const SyncState();
    final last = ref.watch(_lastSyncProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            GallaHeader(title: l10n.settingsTitle, showBack: true),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding, vertical: 8),
              child: GallaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.menuSyncStatus, style: GallaText.heading),
                    const SizedBox(height: 10),
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: SyncStatusChip()),
                    const SizedBox(height: 10),
                    Text(
                      last == null
                          ? l10n.syncNever
                          : l10n.syncLast(
                              DateFormat('d MMM, h:mm a').format(last)),
                      style: GallaText.body.copyWith(color: GallaColors.muted),
                    ),
                    if (state.failure != null) ...[
                      const SizedBox(height: 8),
                      Text(_failureText(l10n, state.failure!),
                          style: GallaText.bodyMedium
                              .copyWith(color: GallaColors.danger)),
                    ],
                    if (state.stuck > 0) ...[
                      const SizedBox(height: 8),
                      Text(l10n.syncStuck(state.stuck),
                          style: GallaText.bodyMedium
                              .copyWith(color: GallaColors.danger)),
                    ],
                    const SizedBox(height: 14),
                    GallaPrimaryButton(
                      label: state.running ? l10n.syncRunning : l10n.syncNowButton,
                      icon: Icons.sync,
                      onPressed: state.running ? null : _syncNow,
                      height: 52,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding, vertical: 8),
              child: GallaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.backupTitle, style: GallaText.heading),
                    const SizedBox(height: 6),
                    Text(l10n.backupHint,
                        style:
                            GallaText.body.copyWith(color: GallaColors.muted)),
                    const SizedBox(height: 14),
                    GallaOutlineButton(
                      label: l10n.backupButton,
                      icon: Icons.download_outlined,
                      height: 52,
                      onPressed: _exporting ? null : _backup,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.aboutVersion(AppInfo.version),
                        style:
                            GallaText.caption.copyWith(color: GallaColors.muted)),
                  ),
                  if (AppInfo.privacyUrl.isNotEmpty)
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse(AppInfo.privacyUrl),
                          mode: LaunchMode.externalApplication),
                      child: Text(l10n.privacyPolicy),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
