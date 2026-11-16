import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../../bill/domain/bill_math.dart' show lineTotal;
import '../data/purchase_repository.dart';

/// One purchase: items with cost, what was paid, and the invoice photo.
class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(purchaseDetailProvider(purchaseId));
    return Scaffold(
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (d) {
            if (d == null) return const SizedBox.shrink();
            final p = d.purchase;
            final unpaid = p.total - p.paidAmount;
            return Column(
              children: [
                GallaHeader(
                  title: p.purchaseNo.isEmpty
                      ? l10n.purchaseDetailTitleNoNo
                      : l10n.purchaseDetailTitle(p.purchaseNo),
                  subtitle: d.supplierName,
                  showBack: true,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                        4, GallaSizes.screenPadding, 24),
                    children: [
                      GallaCard(
                        hero: true,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            _Row(l10n.purchaseTotal, p.total),
                            _Row(l10n.purchasePaidNow, p.paidAmount),
                            _Row(l10n.supplierDena, unpaid, big: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.purchaseItems, style: GallaText.heading),
                      for (final v in d.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: GallaCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(v.itemName,
                                          style: GallaText.display
                                              .copyWith(fontSize: 17)),
                                      Text(
                                        l10n.purchaseCostLine(
                                            formatPaisaPlain(v.line.unitCost),
                                            formatQty(v.line.qty),
                                            unitLabel(l10n, v.unit)),
                                        style: GallaText.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                MoneyText(
                                    lineTotal(v.line.qty, v.line.unitCost),
                                    size: 17,
                                    symbol: false),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(l10n.purchaseSaboot, style: GallaText.heading),
                      const SizedBox(height: 6),
                      if (p.invoiceImagePath == null &&
                          p.invoiceImageUrl == null)
                        Text(l10n.purchaseNoPhoto, style: GallaText.caption)
                      else if (p.invoiceImagePath == null)
                        // Photo taken on another phone / restored from the
                        // server: show the remote copy.
                        ClipRRect(
                          borderRadius: GallaRadius.card,
                          child: Image.network(
                            p.invoiceImageUrl!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 180,
                              color: GallaColors.chip,
                              alignment: Alignment.center,
                              child: Text(l10n.purchaseNoPhoto),
                            ),
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => InvoiceViewer(
                                    path: p.invoiceImagePath!)),
                          ),
                          child: ClipRRect(
                            borderRadius: GallaRadius.card,
                            child: Image.file(
                              File(p.invoiceImagePath!),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 900,
                              errorBuilder: (_, __, ___) => Container(
                                height: 180,
                                color: GallaColors.chip,
                                alignment: Alignment.center,
                                child: Text(l10n.purchaseNoPhoto),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            context.push('/supplier/${p.supplierId}'),
                        child: Text(l10n.supplierTitle),
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.paisa, {this.big = false});

  final String label;
  final int paisa;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GallaText.body.copyWith(color: GallaColors.chip)),
          ),
          MoneyText(paisa, size: big ? 22 : 18, tone: MoneyTone.onDark),
        ],
      ),
    );
  }
}

/// Full-screen, pinch to zoom.
class InvoiceViewer extends StatelessWidget {
  const InvoiceViewer({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
