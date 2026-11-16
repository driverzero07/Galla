import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/daos/khata_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/party_repository.dart';
import 'party_form_sheet.dart';

/// Customer or Supplier list (opened from Menu): search, add, edit, hide.
/// Tapping a row opens its khata (edit is in the khata's menu).
class PartyListScreen extends ConsumerStatefulWidget {
  const PartyListScreen({super.key, required this.kind});

  final PartyKind kind;

  @override
  ConsumerState<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends ConsumerState<PartyListScreen> {
  String _query = '';
  bool _showHidden = false;

  bool get _isCustomer => widget.kind == PartyKind.customer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(partyListProvider(
        (kind: widget.kind, query: _query, showHidden: _showHidden)));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(
              title: _isCustomer ? l10n.customersTitle : l10n.suppliersTitle,
              showBack: true,
              trailing: GallaPillButton(
                label: _isCustomer ? l10n.khataAddCustomer : l10n.supplierAdd,
                onPressed: () => showPartyForm(context, kind: widget.kind),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: GallaChip(
                  label: l10n.partyShowHidden,
                  icon: _showHidden
                      ? Icons.visibility
                      : Icons.visibility_off_outlined,
                  tone: _showHidden
                      ? GallaChipTone.selected
                      : GallaChipTone.normal,
                  onTap: () => setState(() => _showHidden = !_showHidden),
                ),
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
                      icon: _isCustomer
                          ? Icons.person_outline
                          : Icons.local_shipping_outlined,
                      message: searching
                          ? l10n.partyNoMatch
                          : (_isCustomer
                              ? l10n.customersEmpty
                              : l10n.suppliersEmpty),
                      actionLabel: searching
                          ? null
                          : (_isCustomer
                              ? l10n.khataAddCustomer
                              : l10n.supplierAdd),
                      onAction: () =>
                          showPartyForm(context, kind: widget.kind),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _PartyTile(
                      row: rows[i],
                      isCustomer: _isCustomer,
                      onTap: () => context.push(_isCustomer
                          ? '/khata/${rows[i].id}'
                          : '/supplier/${rows[i].id}'),
                    ),
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

class _PartyTile extends StatelessWidget {
  const _PartyTile({
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
    final initial = row.name.trim().isEmpty ? '?' : row.name.trim()[0].toUpperCase();
    final phone = row.phone;
    final isAdvance = row.balance < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: row.isArchived ? 0.55 : 1,
        child: GallaCard(
          onTap: onTap,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: GallaColors.chip,
                  shape: BoxShape.circle,
                ),
                child: Text(initial,
                    style: GallaText.display.copyWith(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        style: GallaText.display.copyWith(fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (phone != null && phone.isNotEmpty)
                      Text(displayPkPhone(phone), style: GallaText.caption),
                    if (row.isArchived)
                      Text(l10n.itemHiddenTag, style: GallaText.label),
                  ],
                ),
              ),
              if (row.balance != 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      row.balance.abs(),
                      size: 17,
                      tone: isAdvance
                          ? MoneyTone.received
                          : (isCustomer ? MoneyTone.udhaar : MoneyTone.danger),
                    ),
                    if (isAdvance)
                      Text(l10n.partyAdvance, style: GallaText.label),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
