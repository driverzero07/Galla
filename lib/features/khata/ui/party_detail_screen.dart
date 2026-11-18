import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/current_shop.dart';
import '../../customers/data/party_repository.dart';
import '../../customers/ui/party_form_sheet.dart';
import '../data/khata_repository.dart';
import '../data/statement_service.dart';
import '../domain/ledger_history.dart';
import 'history_widgets.dart';

/// Customer khata (Baqaya) or supplier khata (Dena): balance card, two
/// actions and the full history with a running balance. Both screens share
/// this layout, so they cannot drift apart.
class PartyDetailScreen extends ConsumerWidget {
  const PartyDetailScreen({
    super.key,
    required this.partyId,
    required this.isCustomer,
  });

  final String partyId;
  final bool isCustomer;

  PartyKind get _kind => isCustomer ? PartyKind.customer : PartyKind.supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final String name;
    final String? phone;
    if (isCustomer) {
      final c = ref.watch(customerProvider(partyId)).valueOrNull;
      name = c?.name ?? '';
      phone = c?.phone;
    } else {
      final s = ref.watch(supplierProvider(partyId)).valueOrNull;
      name = s?.name ?? '';
      phone = s?.phone;
    }
    final history = ref
        .watch(isCustomer
            ? customerHistoryProvider(partyId)
            : supplierHistoryProvider(partyId))
        .valueOrNull;
    final balance = history?.balance ?? 0;

    final subtitle = isCustomer
        ? phone
        : (phone == null ? l10n.suppliersTitle : l10n.supplierLabel(phone));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(
              title: name,
              subtitle: subtitle,
              showBack: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (phone != null)
                    IconButton(
                      tooltip: l10n.khataCall,
                      icon: const Icon(Icons.phone_outlined),
                      onPressed: () => _phoneSheet(context, phone!),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'share') {
                        _share(context, ref, name, phone, history);
                      } else {
                        showPartyForm(context, kind: _kind, partyId: partyId);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'share', child: Text(l10n.khataShare)),
                      PopupMenuItem(
                          value: 'edit', child: Text(l10n.khataEditParty)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 24),
                children: [
                  BalanceHero(
                    label: isCustomer ? l10n.khataBalance : l10n.supplierDena,
                    advanceLabel: isCustomer
                        ? l10n.khataAdvance
                        : l10n.supplierAdvance,
                    balance: balance,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GallaPrimaryButton(
                          lime: true,
                          height: 56,
                          label: isCustomer
                              ? l10n.khataReceived
                              : l10n.supplierPaid,
                          onPressed: () => _pay(context, ref, balance),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GallaOutlineButton(
                          height: 56,
                          label: isCustomer
                              ? l10n.khataAddUdhaar
                              : l10n.supplierNewPurchase,
                          onPressed: () => isCustomer
                              ? _udhaar(context, ref)
                              : context.go('/purchase?supplier=$partyId'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.khataFullHistory, style: GallaText.heading),
                  const SizedBox(height: 4),
                  if (history != null && history.entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message: l10n.khataEmptyHistory,
                      ),
                    )
                  else if (history != null)
                    for (final e in history.entries)
                      HistoryTile(
                        entry: e,
                        isCustomer: isCustomer,
                        onTap: _target(e) == null
                            ? null
                            : () => context.push(_target(e)!),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Where a history row leads: the bill or purchase behind it.
  String? _target(HistoryEntry e) {
    if (e.refId == null || e.docNo == null) return null;
    return isCustomer ? '/bills/${e.refId}' : '/purchases/${e.refId}';
  }

  Future<void> _phoneSheet(BuildContext context, String phone) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text('${l10n.khataCall}  $phone'),
              onTap: () {
                Navigator.pop(ctx);
                openPhone(context, phone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: Text(l10n.khataWhatsApp),
              onTap: () {
                Navigator.pop(ctx);
                openPhone(context, phone, whatsApp: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, int balance) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(khataRepositoryProvider);
    final r = await showEntrySheet(
      context,
      title: isCustomer ? l10n.receivedTitle : l10n.supplierPayTitle,
      confirmLabel: l10n.entrySave,
      fullAmount: balance > 0 ? balance : 0,
    );
    if (r == null) return;
    try {
      if (isCustomer) {
        await repo.receivePayment(partyId, r.amount,
            note: r.note, date: r.date);
      } else {
        await repo.paySupplier(partyId, r.amount, note: r.note, date: r.date);
      }
      messenger.showSnackBar(SnackBar(
          content: Text(isCustomer
              ? l10n.receivedDone(formatPaisa(r.amount))
              : l10n.supplierPaidDone(formatPaisa(r.amount)))));
    } on LedgerEntryException catch (e) {
      final text = e.error == LedgerEntryError.insufficientCash
          ? l10n.cashNotEnough(formatPaisa(e.available))
          : l10n.entryFailed;
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (kDebugMode) debugPrint('payment error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.entryFailed)));
    }
  }

  Future<void> _udhaar(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final r = await showEntrySheet(
      context,
      title: l10n.udhaarTitle,
      confirmLabel: l10n.entrySave,
    );
    if (r == null) return;
    try {
      await ref
          .read(khataRepositoryProvider)
          .addUdhaar(partyId, r.amount, note: r.note, date: r.date);
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.udhaarDone(formatPaisa(r.amount)))));
    } catch (e) {
      if (kDebugMode) debugPrint('udhaar error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.entryFailed)));
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref, String name,
      String? phone, History? history) async {
    final l10n = AppLocalizations.of(context);
    final h = history ??
        (isCustomer
            ? await ref.read(khataRepositoryProvider).customerHistory(partyId)
            : await ref.read(khataRepositoryProvider).supplierHistory(partyId));
    if (!context.mounted) return;
    final shop = ref.read(currentShopProvider).valueOrNull;
    final data = StatementData(
      shopName: shop?.name ?? '',
      partyName: name,
      partyPhone: phone,
      generatedAt: DateTime.now(),
      rows: statementRows(l10n, h, isCustomer: isCustomer),
      balance: h.balance,
    );
    await showShareSheet(context, ref,
        data: data, labels: statementLabels(l10n, isCustomer: isCustomer));
  }
}
