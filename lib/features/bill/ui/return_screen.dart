import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/sales_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../data/sales_repository.dart';
import '../domain/bill_math.dart';
import 'number_entry_dialog.dart';

/// Pick lines and quantities to return. Stock goes back through return_in
/// movements; money still owed comes off the khata, the rest is a cash
/// refund note.
class ReturnScreen extends ConsumerStatefulWidget {
  const ReturnScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  final Map<String, int> _qty = {}; // itemId -> thousandths
  bool _saving = false;

  ReturnPlan _plan(SaleDetailData d) {
    final picked = [
      for (final l in d.lines)
        if ((_qty[l.itemId] ?? 0) > 0) l,
    ];
    return planReturn(
      lines: [
        for (final l in picked) (qty: _qty[l.itemId]!, unitPrice: l.unitPrice),
      ],
      billSubtotal: d.sale.subtotal,
      billDiscount: d.sale.discount,
      billTotal: d.sale.total,
      billPaid: d.sale.paidAmount,
      priorValue: d.returns.fold<int>(0, (s, r) => s + r.amount),
      priorLedgerCredits: d.returns.fold<int>(0, (s, r) => s + r.ledgerCredit),
    );
  }

  void _set(SaleDetailData d, String itemId, int qty, int max) {
    setState(() => _qty[itemId] = qty.clamp(0, max));
  }

  Future<void> _confirm(SaleDetailData d) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = GoRouter.of(context);
    final picked = {
      for (final e in _qty.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (picked.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.returnNothing)));
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(salesRepositoryProvider)
          .createReturn(widget.saleId, picked);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline,
              color: GallaColors.received, size: 36),
          title: Text(l10n.returnDone, style: GallaText.heading),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.ledgerCredit > 0)
                Text(l10n.returnFromKhata(formatPaisa(r.ledgerCredit)),
                    style: GallaText.bodyMedium),
              if (r.cashRefund > 0)
                Text(l10n.returnCashBack(formatPaisa(r.cashRefund)),
                    style: GallaText.bodyMedium),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l10n.ok)),
          ],
        ),
      );
      nav.pop();
    } catch (e) {
      if (kDebugMode) debugPrint('return error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.billActionFailed)));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(saleDetailProvider(widget.saleId));
    return Scaffold(
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (d) {
            if (d == null) return const SizedBox.shrink();
            final plan = _plan(d);
            return Column(
              children: [
                GallaHeader(title: l10n.returnTitle, showBack: true),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: GallaSizes.screenPadding),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.returnPick, style: GallaText.caption),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(GallaSizes.screenPadding),
                    children: [
                      for (final line in d.lines)
                        if (d.returnableQty(line) > 0)
                          _line(l10n, d, line, d.returnableQty(line)),
                      const SizedBox(height: 8),
                      if (plan.total > 0)
                        GallaCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${l10n.returnValue}: ${formatPaisa(plan.total)}',
                                style:
                                    GallaText.display.copyWith(fontSize: 18),
                              ),
                              if (plan.split.ledgerCredit > 0)
                                Text(
                                  l10n.returnFromKhata(
                                      formatPaisa(plan.split.ledgerCredit)),
                                  style: GallaText.body
                                      .copyWith(color: GallaColors.udhaar),
                                ),
                              if (plan.split.cashRefund > 0)
                                Text(
                                  l10n.returnCashBack(
                                      formatPaisa(plan.split.cashRefund)),
                                  style: GallaText.body,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                      8, GallaSizes.screenPadding, 12),
                  child: GallaPrimaryButton(
                    height: 64,
                    label: l10n.returnConfirm,
                    trailing: plan.total > 0 ? formatPaisa(plan.total) : null,
                    onPressed: (_saving || plan.total == 0) ? null : () => _confirm(d),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _line(AppLocalizations l10n, SaleDetailData d, SaleLine line, int max) {
    final qty = _qty[line.itemId] ?? 0;
    final unit = unitLabel(l10n, d.unitOf(line.itemId));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.nameSnapshot,
                      style: GallaText.display.copyWith(fontSize: 17)),
                  Text(
                    '${l10n.returnMax('${formatQty(max)} $unit')}  ·  '
                    '${formatPaisa(line.unitPrice)}',
                    style: GallaText.caption,
                  ),
                ],
              ),
            ),
            _Step(
              icon: Icons.remove,
              onTap: () => _set(d, line.itemId, qty - 1000, max),
            ),
            InkWell(
              onTap: () async {
                final v = await askQuantity(context,
                    title: l10n.qtyDialogTitle, current: qty, unit: unit);
                if (v != null) _set(d, line.itemId, v, max);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    minWidth: 52, minHeight: GallaSizes.touch),
                child: Center(
                  child: Text(formatQty(qty),
                      style: GallaText.display.copyWith(fontSize: 20)),
                ),
              ),
            ),
            _Step(
              icon: Icons.add,
              onTap: () => _set(d, line.itemId, qty + 1000, max),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: GallaSizes.touch,
      height: GallaSizes.touch,
      child: Material(
        color: GallaColors.chip,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, color: GallaColors.ink),
        ),
      ),
    );
  }
}
