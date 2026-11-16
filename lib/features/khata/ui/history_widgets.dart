import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/db/constants.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/statement_service.dart';
import '../domain/ledger_history.dart';

/// "Aaj", "Kal", "3 din pehle", "2 hafte pehle"...
String whenText(AppLocalizations l10n, DateTime now, DateTime date) {
  final d = daysAgo(now, date);
  if (d == 0) return l10n.whenToday;
  if (d == 1) return l10n.whenYesterday;
  if (d < 7) return l10n.whenDays(d);
  if (d < 14) return l10n.whenWeek;
  if (d < 30) return l10n.whenWeeks(d ~/ 7);
  return l10n.whenMonths(d ~/ 30);
}

/// Title of a history row ("Bill #214", "Paisay mile", ...).
String entryTitle(AppLocalizations l10n, HistoryEntry e,
    {required bool isCustomer}) {
  if (isCustomer) {
    switch (e.type) {
      case CustomerLedgerType.saleCredit:
        return l10n.khataBillNo(e.docNo ?? '');
      case CustomerLedgerType.paymentReceived:
        return l10n.histPayment;
      case CustomerLedgerType.manualUdhaar:
        return l10n.histManualUdhaar;
      case CustomerLedgerType.opening:
        return l10n.histOpening;
      case CustomerLedgerType.returnCredit:
        return l10n.histReturn(e.docNo ?? '');
      case CustomerLedgerType.adjustment:
        return e.docNo != null
            ? l10n.histCancel(e.docNo!)
            : l10n.histAdjustment;
    }
    return l10n.histAdjustment;
  }
  switch (e.type) {
    case SupplierLedgerType.purchaseCredit:
      return e.docNo == null
          ? l10n.purchaseDetailTitleNoNo
          : l10n.supplierPurchaseNo(e.docNo!);
    case SupplierLedgerType.paymentMade:
      return l10n.supplierPaid;
    case SupplierLedgerType.opening:
      return l10n.histOpening;
  }
  return l10n.histAdjustment;
}

/// Second line of a history row: items, or the note, or a default.
String? entryDetail(AppLocalizations l10n, HistoryEntry e,
    {required bool isCustomer}) {
  if (e.itemsText != null && e.itemsText!.isNotEmpty) return e.itemsText;
  if (e.note != null && e.note!.isNotEmpty) return e.note;
  if (isCustomer && e.type == CustomerLedgerType.paymentReceived) {
    return l10n.khataCashReceived;
  }
  if (!isCustomer && e.type == SupplierLedgerType.paymentMade) {
    return l10n.supplierCashPaid;
  }
  return null;
}

/// One row of the "Poori history" list.
class HistoryTile extends StatelessWidget {
  const HistoryTile({
    super.key,
    required this.entry,
    required this.isCustomer,
    this.onTap,
  });

  final HistoryEntry entry;
  final bool isCustomer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final e = entry;
    final title = entryTitle(l10n, e, isCustomer: isCustomer);
    final detail = entryDetail(l10n, e, isCustomer: isCustomer);
    final tone = e.amount < 0
        ? MoneyTone.received
        : (isCustomer ? MoneyTone.udhaar : MoneyTone.danger);
    final dateText = '${whenText(l10n, now, e.date)}  ·  '
        '${_shortDate(e.date)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateText, style: GallaText.caption),
                  const SizedBox(height: 2),
                  Text(title,
                      style: GallaText.bodyMedium
                          .copyWith(color: GallaColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (detail != null)
                    Text(detail,
                        style: GallaText.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  if (e.paidNote != null && e.paidNote! > 0)
                    Text(l10n.purchasePaidShort(formatPaisa(e.paidNote!)),
                        style: GallaText.caption
                            .copyWith(color: GallaColors.received)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(e.amount, tone: tone, size: 18, signed: true),
                const SizedBox(height: 4),
                Text(
                  '${l10n.statementBalance}: '
                  '${formatPaisa(e.balanceAfter.abs(), symbol: false)}'
                  '${e.balanceAfter < 0 ? ' (${l10n.khataAdvance})' : ''}',
                  style: GallaText.caption,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// The big Baqaya / Dena card.
class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.label,
    required this.balance,
    required this.advanceLabel,
  });

  final String label;
  final int balance;

  /// Shown instead of [label] when the balance is negative (an advance).
  final String advanceLabel;

  @override
  Widget build(BuildContext context) {
    return GallaCard(
      hero: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(balance < 0 ? advanceLabel : label,
              style: GallaText.bodyMedium.copyWith(color: GallaColors.chip)),
          const SizedBox(height: 4),
          MoneyText(balance.abs(), size: 44, tone: MoneyTone.onDark),
        ],
      ),
    );
  }
}

/// What the amount sheet returns.
class EntryResult {
  const EntryResult(this.amount, this.note, this.date);
  final int amount;
  final String? note;
  final DateTime date;
}

/// Amount sheet used for Paisay mile, Udhaar likho and Paisay diye.
/// [fullAmount] > 0 shows the "Poora baqaya" quick button.
Future<EntryResult?> showEntrySheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  int fullAmount = 0,
}) {
  return showModalBottomSheet<EntryResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EntrySheet(
        title: title, confirmLabel: confirmLabel, fullAmount: fullAmount),
  );
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    required this.title,
    required this.confirmLabel,
    required this.fullAmount,
  });

  final String title;
  final String confirmLabel;
  final int fullAmount;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _invalid = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (d != null) setState(() => _date = d);
  }

  void _submit() {
    final paisa = parseRupeesToPaisa(_amount.text);
    if (paisa == null || paisa <= 0) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, EntryResult(paisa, _note.text.trim(), _date));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isToday = daysAgo(DateTime.now(), _date) == 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          GallaSizes.screenPadding,
          0,
          GallaSizes.screenPadding,
          MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: GallaText.heading),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: GallaText.display.copyWith(fontSize: 28),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              decoration: InputDecoration(
                prefixText: 'Rs ',
                hintText: l10n.entryAmount,
                errorText: _invalid ? l10n.entryAmountInvalid : null,
              ),
            ),
            if (widget.fullAmount > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: Text(
                      '${l10n.entryFull}: ${formatPaisa(widget.fullAmount)}'),
                  onPressed: () => setState(() {
                    _amount.text = formatPaisaPlain(widget.fullAmount);
                    _invalid = false;
                  }),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: l10n.entryNote),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text(
                    '${l10n.entryDate}: ${isToday ? l10n.whenToday : _shortDate(_date)}'),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GallaColors.lime,
                  foregroundColor: GallaColors.ink,
                ),
                onPressed: _submit,
                child: Text(widget.confirmLabel,
                    style: GallaText.buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the phone dialler or WhatsApp. Failures show a snackbar.
Future<void> openPhone(BuildContext context, String phone,
    {bool whatsApp = false}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final uri = whatsApp
      ? Uri.parse('https://wa.me/$digits')
      : Uri(scheme: 'tel', path: phone);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(l10n.launchFailed)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.launchFailed)));
  }
}

/// Bottom sheet "Statement bhejo": PDF or WhatsApp text.
Future<void> showShareSheet(
  BuildContext context,
  WidgetRef ref, {
  required StatementData data,
  required StatementLabels labels,
}) {
  final l10n = AppLocalizations.of(context);
  final actions = ref.read(statementActionsProvider);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.khataSharePdf),
            onTap: () {
              Navigator.pop(ctx);
              actions.share(data, labels);
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(l10n.khataShareText),
            onTap: () {
              Navigator.pop(ctx);
              actions.shareText(data, labels);
            },
          ),
        ],
      ),
    ),
  );
}

StatementLabels statementLabels(AppLocalizations l10n,
        {required bool isCustomer}) =>
    StatementLabels(
      title: isCustomer ? l10n.statementCustomer : l10n.statementSupplier,
      balanceLabel: isCustomer ? l10n.khataBalance : l10n.supplierDena,
      advanceLabel: isCustomer ? l10n.khataAdvance : l10n.supplierAdvance,
      date: l10n.statementDate,
      detail: l10n.statementDetail,
      amount: l10n.statementAmount,
      balance: l10n.statementBalance,
      moreRows: (n) => l10n.statementMore(n),
      thanks: l10n.statementThanks,
    );

/// Oldest-first rows for the statement.
List<StatementRow> statementRows(
  AppLocalizations l10n,
  History h, {
  required bool isCustomer,
}) =>
    [
      for (final e in h.entries.reversed)
        StatementRow(
          date: e.date,
          title: entryTitle(l10n, e, isCustomer: isCustomer),
          detail: entryDetail(l10n, e, isCustomer: isCustomer),
          amount: e.amount,
          balance: e.balanceAfter,
        ),
    ];
