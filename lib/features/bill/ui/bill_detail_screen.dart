import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/constants.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/sales_repository.dart';
import 'sale_summary.dart';

/// One bill with Return and Cancel (cancel always asks first).
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key, required this.saleId});

  final String saleId;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: GallaColors.danger, size: 36),
        title: Text(l10n.billCancelTitle, style: GallaText.heading),
        content: Text(l10n.billCancelBody, style: GallaText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.stockLowNo)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: GallaColors.danger,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.billCancelYes),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(salesRepositoryProvider).cancelSale(saleId);
      ref.invalidate(saleDetailProvider(saleId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.billCancelledDone)));
    } catch (e) {
      if (kDebugMode) debugPrint('cancel error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.billActionFailed)));
    }
  }

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
            final active = d.sale.status == DocStatus.active;
            return Column(
              children: [
                GallaHeader(
                  title: l10n.billDetailTitle(d.sale.billNo),
                  showBack: true,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                        4, GallaSizes.screenPadding, 16),
                    children: [
                      SaleSummary(detail: d),
                      const SizedBox(height: 16),
                      ReceiptButtons(detail: d),
                      if (active) ...[
                        const SizedBox(height: 16),
                        if (d.canReturn)
                          GallaOutlineButton(
                            icon: Icons.undo,
                            label: l10n.billReturn,
                            onPressed: () async {
                              await context.push('/bills/$saleId/return');
                              ref.invalidate(saleDetailProvider(saleId));
                            },
                          ),
                        const SizedBox(height: 10),
                        _DangerButton(
                          label: l10n.billCancel,
                          onPressed: () => _cancel(context, ref),
                        ),
                      ],
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

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: GallaColors.dangerBg,
        shape: RoundedRectangleBorder(
          borderRadius: GallaRadius.card,
          side: const BorderSide(color: GallaColors.dangerBorder),
        ),
        child: InkWell(
          borderRadius: GallaRadius.card,
          onTap: onPressed,
          child: Center(
            child: Text(label,
                style: GallaText.buttonLabel
                    .copyWith(fontSize: 17, color: GallaColors.danger)),
          ),
        ),
      ),
    );
  }
}
