import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inventory/ui/item_thumb.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../data/home_providers.dart';
import '../domain/dashboard.dart';

/// The bell: low stock and sync problems.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final alerts = ref.watch(alertsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(title: l10n.alertsTitle, showBack: true),
            Expanded(
              child: alerts.isEmpty
                  ? EmptyState(
                      icon: Icons.notifications_none,
                      message: l10n.alertsEmpty,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          GallaSizes.screenPadding,
                          4,
                          GallaSizes.screenPadding,
                          24),
                      children: [
                        for (final a in alerts)
                          switch (a) {
                            final LowStockAlert low => _LowCard(alert: low),
                            final SyncAlert sync => _SyncCard(alert: sync),
                          },
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowCard extends StatelessWidget {
  const _LowCard({required this.alert});

  final LowStockAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = lowestStock(alert.items, limit: 10);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GallaCard(
        onTap: () => context.push('/saman?low=1'),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: GallaColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.alertLowStock(alert.count),
                      style: GallaText.heading.copyWith(fontSize: 17)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final e in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    ItemThumb(
                        name: e.item.name,
                        photoPath: e.item.photoPath,
 photoUrl: e.item.photoUrl,
                        size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.item.name,
                          style: GallaText.bodyMedium
                              .copyWith(color: GallaColors.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      '${formatQty(e.stock)} ${unitLabel(l10n, e.item.unit)}',
                      style: GallaText.label.copyWith(
                          color: e.stock <= 0
                              ? GallaColors.danger
                              : GallaColors.muted,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(l10n.alertLowStockOpen,
                style: GallaText.bodyMedium
                    .copyWith(color: GallaColors.ink, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.alert});

  final SyncAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GallaCard(
        color: GallaColors.warningBg,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: GallaColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.alertSyncOffline(alert.pending),
                  style: GallaText.body),
            ),
          ],
        ),
      ),
    );
  }
}
