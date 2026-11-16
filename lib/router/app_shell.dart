import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/notifications/low_stock_notifier.dart';
import '../core/widgets/galla_nav_bar.dart';
import '../features/home/data/home_providers.dart';
import '../l10n/gen/app_localizations.dart';

/// Shell with the bottom nav: Khata, Bill (centre), Purchase. Home is also
/// inside the shell but has no tab highlighted; it is reached via the G logo.
///
/// It also keeps the daily 9 am low-stock notification in step with stock,
/// for as long as the owner is logged in.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(lowItemsProvider, (_, __) {
      // After the first frame: localisations are not readable in initState.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncNotification());
    }, fireImmediately: true);
  }

  void _syncNotification() {
    if (!mounted) return;
    final low = ref.read(lowItemsProvider).valueOrNull;
    if (low == null) return;
    final l10n = AppLocalizations.of(context);
    ref.read(lowStockNotifierProvider).sync(
          anyLow: low.isNotEmpty,
          texts: LowStockTexts(
            title: l10n.notifLowTitle,
            body: l10n.notifLowBody,
            channelName: l10n.notifChannelName,
            channelDescription: l10n.notifChannelDesc,
          ),
        );
  }

  GallaNavItem? get _selected {
    final location = widget.location;
    if (location.startsWith('/khata')) return GallaNavItem.khata;
    if (location.startsWith('/purchase')) return GallaNavItem.purchase;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: GallaNavBar(
        selected: _selected,
        khataLabel: l10n.navKhata,
        billLabel: l10n.navBill,
        purchaseLabel: l10n.navPurchase,
        onSelected: (item) {
          switch (item) {
            case GallaNavItem.khata:
              context.go('/khata');
            case GallaNavItem.purchase:
              context.go('/purchase');
            case GallaNavItem.bill:
              context.push('/bill');
          }
        },
      ),
    );
  }
}
