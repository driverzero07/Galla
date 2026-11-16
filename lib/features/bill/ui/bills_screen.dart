import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/db/constants.dart';
import '../../../core/db/daos/sales_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/sales_repository.dart';

/// Aj ki bikri: today's bills, newest first. Tap a bill for its detail.
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bills = ref.watch(todaySalesProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(title: l10n.billsTodayTitle, showBack: true),
            Expanded(
              child: bills.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) {
                  if (rows.isEmpty) {
                    return EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: l10n.billsEmpty,
                      actionLabel: l10n.billNewAgain,
                      onAction: () => context.push('/bill'),
                    );
                  }
                  final total = rows
                      .where((r) => r.sale.status == DocStatus.active)
                      .fold<int>(0, (s, r) => s + r.sale.total);
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                        4, GallaSizes.screenPadding, 24),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GallaCard(
                            hero: true,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(l10n.billsTodayTotal,
                                      style: GallaText.bodyMedium.copyWith(
                                          color: GallaColors.chip)),
                                ),
                                MoneyText(total,
                                    size: 28, tone: MoneyTone.onDark),
                              ],
                            ),
                          ),
                        );
                      }
                      return _BillTile(row: rows[i - 1]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.row});

  final SaleListRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = row.sale;
    final cancelled = s.status == DocStatus.cancelled;
    final isUdhaar = s.paymentMode != PaymentMode.cash;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        onTap: () => context.push('/bills/${s.id}'),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l10n.receiptBill} #${s.billNo}',
                      style: GallaText.display.copyWith(fontSize: 17)),
                  Text(
                    '${DateFormat('h:mm a').format(s.createdAt)}  ·  '
                    '${row.customerName}',
                    style: GallaText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Opacity(
                  opacity: cancelled ? 0.5 : 1,
                  child: MoneyText(s.total,
                      size: 17,
                      tone: (isUdhaar && !cancelled)
                          ? MoneyTone.udhaar
                          : MoneyTone.ink),
                ),
                if (cancelled)
                  Text(l10n.billCancelledTag,
                      style: GallaText.label.copyWith(
                          color: GallaColors.danger,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
