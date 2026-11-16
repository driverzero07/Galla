import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/daos/inventory_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_logo.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/current_shop.dart';
import '../../inventory/ui/item_thumb.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../data/home_providers.dart';
import '../domain/dashboard.dart';

/// Home: every number is a live query, so it changes the moment a bill,
/// payment or stock movement is saved.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shop = ref.watch(currentShopProvider).valueOrNull;
    final today = ref.watch(todaySummaryProvider).valueOrNull ??
        const TodaySummary();
    final lena = ref.watch(lenaProvider);
    final dena = ref.watch(denaProvider);
    final alerts = ref.watch(alertsProvider);
    final badge = alertCount(alerts);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            GallaSizes.screenPadding, 12, GallaSizes.screenPadding, 24),
        children: [
          Row(
            children: [
              const GallaLogo(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.homeGreeting, style: GallaText.caption),
                    Text(
                      shop?.ownerName ?? shop?.name ?? '',
                      style: GallaText.heading.copyWith(fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _RoundIconButton(
                icon: Icons.notifications_none,
                tooltip: l10n.notifications,
                badge: badge,
                onTap: () => context.push('/alerts'),
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: Icons.more_horiz,
                tooltip: l10n.more,
                onTap: () => context.push('/menu'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: SyncStatusChip(),
          ),
          const SizedBox(height: 8),
          GallaCard(
            hero: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            onTap: () => context.push('/bills'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.homeTodaySales,
                    style: GallaText.bodyMedium
                        .copyWith(color: GallaColors.chip)),
                const SizedBox(height: 2),
                MoneyText(today.total, size: 44, tone: MoneyTone.onDark),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _DarkChip(l10n.homeCash(
                        formatPaisa(today.cash, symbol: false))),
                    _DarkChip(l10n.homeUdhaar(
                        formatPaisa(today.udhaar, symbol: false))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GallaCard(
            color: GallaColors.lime,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.homeTodayProfit, style: GallaText.bodyMedium),
                const SizedBox(height: 2),
                MoneyText(today.profit, size: 40),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _OwedCard(
                  title: l10n.homeLena,
                  total: lena.total,
                  chip: l10n.homeCustomerCount(lena.count),
                  onTap: () => context.go('/khata'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OwedCard(
                  title: l10n.homeDena,
                  total: dena.total,
                  chip: l10n.homeSupplierCount(dena.count),
                  onTap: () => context.push('/suppliers'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _LowStockCard(),
        ],
      ),
    );
  }
}

class _OwedCard extends StatelessWidget {
  const _OwedCard({
    required this.title,
    required this.total,
    required this.chip,
    required this.onTap,
  });

  final String title;
  final int total;
  final String chip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GallaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GallaText.bodyMedium.copyWith(color: GallaColors.ink)),
          const SizedBox(height: 4),
          MoneyText(total, size: 24),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GallaColors.chip,
              borderRadius: BorderRadius.circular(GallaRadius.round),
            ),
            child: Text(chip, style: GallaText.label),
          ),
        ],
      ),
    );
  }
}

/// "Khatam Hona wala saman": the 3 lowest items; first-day empty state.
class _LowStockCard extends ConsumerWidget {
  const _LowStockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final low = ref.watch(lowItemsProvider).valueOrNull ?? const [];
    final itemCount = ref.watch(itemCountProvider).valueOrNull;
    final top = lowestStock(low);

    Widget body;
    if (itemCount == 0) {
      // First day: one clear next step.
      body = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            Text(l10n.homeNoItems,
                style: GallaText.body, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            GallaPrimaryButton(
              lime: true,
              height: 56,
              icon: Icons.add,
              label: l10n.homeAddFirstItem,
              onPressed: () => context.push('/saman/add'),
            ),
          ],
        ),
      );
    } else if (top.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: GallaColors.received),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.homeStockOk, style: GallaText.body)),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          for (final e in top) _LowRow(entry: e),
          InkWell(
            onTap: () => context.push('/saman?low=1'),
            child: SizedBox(
              height: GallaSizes.touch,
              width: double.infinity,
              child: Center(
                child: Text(low.length > top.length
                    ? '${l10n.homeMore}  (${low.length})'
                    : l10n.homeMore,
                    style: GallaText.heading),
              ),
            ),
          ),
        ],
      );
    }

    return GallaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeLowStockTitle,
              style: GallaText.heading.copyWith(fontSize: 17)),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}

class _LowRow extends StatelessWidget {
  const _LowRow({required this.entry});

  final ItemWithStock entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = unitLabel(l10n, entry.item.unit);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          ItemThumb(
              name: entry.item.name, photoPath: entry.item.photoPath,
 photoUrl: entry.item.photoUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(entry.item.name,
                style: GallaText.bodyMedium
                    .copyWith(color: GallaColors.ink, fontSize: 17),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: GallaColors.lime,
              borderRadius: BorderRadius.circular(GallaRadius.round),
            ),
            child: Text(
              l10n.homeLeftQty('${formatQty(entry.stock)} $unit'),
              style: GallaText.label.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GallaRadius.round),
      ),
      child: Text(text,
          style: GallaText.label.copyWith(color: GallaColors.chip)),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: GallaColors.card,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Icon(icon, color: GallaColors.ink),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                right: -2,
                top: -2,
                child: IgnorePointer(
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: GallaColors.danger,
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.all(Radius.circular(9)),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
