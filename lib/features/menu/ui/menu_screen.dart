import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/galla_logo.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/current_shop.dart';
import '../../customers/data/party_repository.dart';
import '../../inventory/data/inventory_repository.dart';

/// "Aur" / Menu: Customer, Supplier, Inventory, Migration, Settings.
/// Counts and the PIN change come in later parts.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shop = ref.watch(currentShopProvider).valueOrNull;
    final customers = ref.watch(customerCountProvider).valueOrNull;
    final suppliers = ref.watch(supplierCountProvider).valueOrNull;
    final low = ref.watch(lowStockCountProvider).valueOrNull ?? 0;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            GallaHeader(title: l10n.menuTitle, showBack: true),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding, vertical: 8),
              child: GallaCard(
                hero: true,
                child: Row(
                  children: [
                    const GallaLogo(size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop?.name ?? l10n.appName,
                            style: GallaText.heading.copyWith(
                                color: GallaColors.lime, fontSize: 20),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (shop != null)
                            Text(
                              displayPkPhone(shop.phone),
                              style: GallaText.body
                                  .copyWith(color: GallaColors.chip),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _MenuRow(
              icon: Icons.person_outline,
              label: l10n.menuCustomer,
              trailing: customers == null ? null : _Count('$customers'),
              onTap: () => context.push('/customers'),
            ),
            _MenuRow(
              icon: Icons.local_shipping_outlined,
              label: l10n.menuSupplier,
              trailing: suppliers == null ? null : _Count('$suppliers'),
              onTap: () => context.push('/suppliers'),
            ),
            _MenuRow(
              icon: Icons.inventory_2_outlined,
              label: l10n.menuInventory,
              trailing: low > 0
                  ? GallaChip(
                      label: l10n.menuLowBadge(low),
                      tone: GallaChipTone.danger,
                    )
                  : null,
              onTap: () => context.push('/saman'),
            ),
            _MenuRow(
              icon: Icons.download_outlined,
              label: l10n.menuMigration,
              chevron: true,
              onTap: () => context.push('/migration'),
            ),
            _MenuRow(
              icon: Icons.sync,
              label: l10n.menuSyncBackup,
              chevron: true,
              onTap: () => context.push('/settings'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GallaSizes.screenPadding, 20, GallaSizes.screenPadding, 8),
              child: Text(l10n.menuSettings, style: GallaText.heading.copyWith(fontSize: 16)),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: GallaSizes.screenPadding),
              child: GallaCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _SettingRow(
                      label: l10n.menuLanguage,
                      trailing: Text(l10n.menuLanguageValue,
                          style: GallaText.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const Divider(),
                    _SettingRow(
                      label: l10n.menuSyncStatus,
                      trailing: const SyncStatusChip(),
                    ),
                    const Divider(),
                    _SettingRow(
                      label: l10n.menuChangePin,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
            if (kDebugMode && Env.enableDebugTools)
              _MenuRow(
                icon: Icons.bug_report_outlined,
                // Debug builds only, deliberately not localised.
                label: 'Debug: all screens',
                chevron: true,
                onTap: () => context.push('/debug'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.chevron = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool chevron;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: GallaSizes.screenPadding, vertical: 4),
      child: GallaCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: GallaColors.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: GallaText.display.copyWith(fontSize: 17)),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
            if (chevron || trailing != null)
              const Icon(Icons.chevron_right, color: GallaColors.ink),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GallaText.body)),
          Flexible(child: Align(alignment: Alignment.centerRight, child: trailing)),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: GallaText.display.copyWith(fontSize: 17));
}
