import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../customers/data/party_repository.dart';
import '../../customers/ui/party_form_sheet.dart';

/// Result of the picker. [id] null means the Naqad customer.
class PickedCustomer {
  const PickedCustomer(this.id, this.name);
  final String? id;
  final String name;
}

/// Customer picker with search and "+ Naya customer". Hidden customers do
/// not appear (Part 0 rule 4).
Future<PickedCustomer?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<PickedCustomer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _CustomerPicker(),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _query = '';

  Future<void> _addNew() async {
    final nav = Navigator.of(context);
    final id = await showPartyForm(context, kind: PartyKind.customer);
    if (id == null) return;
    final info = await ref.read(customerRepositoryProvider).info(id);
    if (info != null) nav.pop(PickedCustomer(info.id, info.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(partyListProvider(
        (kind: PartyKind.customer, query: _query, showHidden: false)));
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.billPickCustomerTitle,
                        style: GallaText.heading),
                  ),
                  TextButton(
                    onPressed: _addNew,
                    child: Text(l10n.billNewCustomer,
                        style: GallaText.bodyMedium
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GallaSizes.screenPadding),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l10n.khataSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: GallaSizes.screenPadding),
                children: [
                  if (_query.trim().isEmpty)
                    _Row(
                      icon: Icons.person_outline,
                      name: l10n.billNaqadCustomer,
                      onTap: () => Navigator.of(context)
                          .pop(PickedCustomer(null, l10n.billNaqadCustomer)),
                    ),
                  ...list.maybeWhen(
                    data: (rows) => [
                      for (final r in rows)
                        _Row(
                          icon: Icons.person,
                          name: r.name,
                          caption: r.phone,
                          onTap: () => Navigator.of(context)
                              .pop(PickedCustomer(r.id, r.name)),
                        ),
                    ],
                    orElse: () => const <Widget>[],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.name,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final String name;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: GallaColors.chip, shape: BoxShape.circle),
              child: Icon(icon, color: GallaColors.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GallaText.display.copyWith(fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (caption != null && caption!.isNotEmpty)
                    Text(caption!, style: GallaText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
