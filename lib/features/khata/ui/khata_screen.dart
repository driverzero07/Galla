import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/daos/khata_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../customers/data/party_repository.dart';
import '../../customers/ui/party_form_sheet.dart';
import '../domain/ledger_history.dart';
import 'history_widgets.dart';

/// Khata tab: who owes us, biggest first (or most recent first).
class KhataScreen extends ConsumerStatefulWidget {
  const KhataScreen({super.key});

  @override
  ConsumerState<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends ConsumerState<KhataScreen> {
  String _query = '';
  KhataSort _sort = KhataSort.highest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(partyListProvider(
        (kind: PartyKind.customer, query: '', showHidden: false)));
    final list = ref.watch(partyListProvider(
        (kind: PartyKind.customer, query: _query, showHidden: false)));
    final lena = lenaSummary(
        (all.valueOrNull ?? const <PartyRow>[]).map((r) => r.balance));

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          GallaHeader(
            title: l10n.khataTitle,
            trailing: GallaPillButton(
              label: l10n.khataAddCustomer,
              onPressed: () =>
                  showPartyForm(context, kind: PartyKind.customer),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: GallaSizes.screenPadding, vertical: 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.khataSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: GallaSizes.screenPadding, vertical: 4),
            child: GallaCard(
              hero: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.khataLenaTotal,
                            style: GallaText.bodyMedium
                                .copyWith(color: GallaColors.chip)),
                        MoneyText(lena.total,
                            size: 34, tone: MoneyTone.onDark),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(GallaRadius.round),
                    ),
                    child: Text(l10n.khataOwingCount(lena.owing),
                        style: GallaText.label
                            .copyWith(color: GallaColors.chip)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: GallaSizes.screenPadding, vertical: 4),
            child: Row(
              children: [
                GallaChip(
                  label: l10n.khataSortHighest,
                  tone: _sort == KhataSort.highest
                      ? GallaChipTone.selected
                      : GallaChipTone.normal,
                  onTap: () => setState(() => _sort = KhataSort.highest),
                ),
                const SizedBox(width: 8),
                GallaChip(
                  label: l10n.khataSortRecent,
                  tone: _sort == KhataSort.recent
                      ? GallaChipTone.selected
                      : GallaChipTone.normal,
                  onTap: () => setState(() => _sort = KhataSort.recent),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (rows) {
                if (rows.isEmpty) {
                  final searching = _query.trim().isNotEmpty;
                  return EmptyState(
                    icon: Icons.person_outline,
                    message:
                        searching ? l10n.partyNoMatch : l10n.customersEmpty,
                    actionLabel: searching ? null : l10n.khataAddCustomer,
                    onAction: () =>
                        showPartyForm(context, kind: PartyKind.customer),
                  );
                }
                final sorted = sortParties<PartyRow>(
                  rows,
                  _sort,
                  balance: (r) => r.balance,
                  last: (r) => r.lastActivity,
                  name: (r) => r.name,
                );
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                      4, GallaSizes.screenPadding, 120),
                  itemCount: sorted.length,
                  itemBuilder: (context, i) => PartyBalanceTile(
                    row: sorted[i],
                    isCustomer: true,
                    onTap: () => context.push('/khata/${sorted[i].id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar letter, name, "Aakhri: ..." and the balance on the right.
class PartyBalanceTile extends StatelessWidget {
  const PartyBalanceTile({
    super.key,
    required this.row,
    required this.isCustomer,
    required this.onTap,
  });

  final PartyRow row;
  final bool isCustomer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final last = row.lastActivity;
    final sub = last == null
        ? l10n.khataNoActivity
        : l10n.khataLastSeen(whenText(l10n, DateTime.now(), last));
    final letter =
        row.name.trim().isEmpty ? '?' : row.name.trim()[0].toUpperCase();
    final b = row.balance;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: GallaColors.chip, shape: BoxShape.circle),
              child: Text(letter,
                  style: GallaText.display.copyWith(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name,
                      style: GallaText.bodyMedium
                          .copyWith(color: GallaColors.ink, fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(sub, style: GallaText.caption),
                ],
              ),
            ),
            if (b < 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      isCustomer ? l10n.khataAdvance : l10n.supplierAdvance,
                      style: GallaText.label
                          .copyWith(color: GallaColors.received)),
                  MoneyText(b.abs(),
                      size: 18, tone: MoneyTone.received, symbol: false),
                ],
              )
            else
              MoneyText(
                b,
                size: 18,
                symbol: false,
                tone: b == 0
                    ? MoneyTone.ink
                    : (isCustomer ? MoneyTone.udhaar : MoneyTone.danger),
              ),
          ],
        ),
      ),
    );
  }
}
