import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/sales_repository.dart';
import 'sale_summary.dart';

/// Bill ban gaya: total, lines, stock note, Share, Print, Naya Bill, Home.
class BillDoneScreen extends ConsumerWidget {
  const BillDoneScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(saleDetailProvider(saleId));
    return Scaffold(
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (d) {
            if (d == null) return const SizedBox.shrink();
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(GallaSizes.screenPadding),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                                color: GallaColors.lime,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check,
                                color: GallaColors.ink, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Text(l10n.billDoneTitle, style: GallaText.heading),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SaleSummary(detail: d),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GallaChip(
                          label: l10n.billDoneStockAuto,
                          icon: Icons.inventory_2_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ReceiptButtons(detail: d),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                      0, GallaSizes.screenPadding, 12),
                  child: Column(
                    children: [
                      GallaPrimaryButton(
                        height: 64,
                        label: l10n.billNewAgain,
                        onPressed: () => context.pushReplacement('/bill'),
                      ),
                      const SizedBox(height: 8),
                      GallaOutlineButton(
                        label: l10n.billGoHome,
                        onPressed: () => context.go('/home'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
