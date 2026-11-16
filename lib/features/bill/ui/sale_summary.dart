import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/sales_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/data/shop_repository.dart';
import '../../auth/domain/current_shop.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../data/receipt_service.dart';
import 'receipt_labels.dart';

bool isNaqadSale(Sale sale) =>
    sale.customerId == naqadCustomerId(sale.shopId);

/// "Nakad", "Nakad · Akram", "Udhaar · Akram", "Aadha udhaar · Akram · ...".
String paymentText(AppLocalizations l10n, SaleDetailData d) {
  final s = d.sale;
  final name = d.customerName;
  final naqad = isNaqadSale(s);
  switch (s.paymentMode) {
    case PaymentMode.udhaar:
      return l10n.billDoneUdhaar(name);
    case PaymentMode.partial:
      return l10n.billDonePartial(name, formatPaisa(s.total - s.paidAmount));
    default:
      return naqad ? l10n.billDoneCash : l10n.billDonePaidCash(name);
  }
}

/// Dark total card, payment line, item lines and discount. Shared by
/// BillDone and the bill detail screen.
class SaleSummary extends StatelessWidget {
  const SaleSummary({super.key, required this.detail});

  final SaleDetailData detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = detail.sale;
    final cancelled = s.status == DocStatus.cancelled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GallaCard(
          hero: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                '${l10n.receiptBill} #${s.billNo}  ·  '
                '${DateFormat('d MMM, h:mm a').format(s.createdAt)}',
                style: GallaText.caption.copyWith(color: GallaColors.chip),
              ),
              const SizedBox(height: 8),
              MoneyText(s.total, size: 40, tone: MoneyTone.onDark),
              const SizedBox(height: 6),
              Text(
                cancelled ? l10n.receiptCancelled : paymentText(l10n, detail),
                textAlign: TextAlign.center,
                style: GallaText.bodyMedium.copyWith(
                  color: cancelled ? GallaColors.dangerBorder : Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GallaCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (final line in detail.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line.nameSnapshot,
                                style: GallaText.display.copyWith(fontSize: 16)),
                            Text(
                              '${formatQty(line.qty)} '
                              '${unitLabel(l10n, detail.unitOf(line.itemId))} '
                              'x ${formatPaisa(line.unitPrice)}',
                              style: GallaText.caption,
                            ),
                            if ((detail.returnedQty[line.itemId] ?? 0) > 0)
                              Text(
                                l10n.billAlreadyReturned(formatQty(
                                    detail.returnedQty[line.itemId]!)),
                                style: GallaText.caption
                                    .copyWith(color: GallaColors.udhaar),
                              ),
                          ],
                        ),
                      ),
                      MoneyText(line.lineTotal, size: 16),
                    ],
                  ),
                ),
              if (s.discount > 0) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                          child:
                              Text(l10n.billDiscount, style: GallaText.body)),
                      Text('- ${formatPaisa(s.discount)}',
                          style: GallaText.display.copyWith(
                              fontSize: 16, color: GallaColors.received)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Share (WhatsApp text + PDF) and Print (system print dialog).
class ReceiptButtons extends ConsumerWidget {
  const ReceiptButtons({super.key, required this.detail});

  final SaleDetailData detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shop = ref.watch(currentShopProvider).valueOrNull;

    Future<void> run(
        Future<void> Function(ReceiptActions, ReceiptData, ReceiptLabels)
            action) async {
      if (shop == null) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        final data = ReceiptData.fromSale(
          detail,
          shop,
          unitLabel: (u) => u.isEmpty ? '' : unitLabel(l10n, u),
          isNaqad: isNaqadSale(detail.sale),
        );
        await action(
            ref.read(receiptActionsProvider), data, receiptLabels(l10n));
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.billActionFailed)));
      }
    }

    return Row(
      children: [
        Expanded(
          child: GallaPrimaryButton(
            lime: true,
            height: 56,
            icon: Icons.share_outlined,
            label: l10n.billShare,
            onPressed: shop == null
                ? null
                : () => run((a, d, l) => a.share(d, l)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GallaOutlineButton(
            height: 56,
            icon: Icons.print_outlined,
            label: l10n.billPrint,
            onPressed: shop == null
                ? null
                : () => run((a, d, l) => a.printReceipt(d, l)),
          ),
        ),
      ],
    );
  }
}
