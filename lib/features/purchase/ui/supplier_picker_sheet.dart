import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../customers/data/party_repository.dart';
import '../../customers/ui/party_form_sheet.dart';

class PickedSupplier {
  const PickedSupplier(this.id, this.name);
  final String id;
  final String name;
}

/// Supplier picker with search and "+ Naya supplier". Hidden suppliers do
/// not appear.
Future<PickedSupplier?> showSupplierPicker(BuildContext context) {
  return showModalBottomSheet<PickedSupplier>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SupplierPicker(),
  );
}

class _SupplierPicker extends ConsumerStatefulWidget {
  const _SupplierPicker();

  @override
  ConsumerState<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends ConsumerState<_SupplierPicker> {
  String _query = '';

  Future<void> _addNew() async {
    final nav = Navigator.of(context);
    final id = await showPartyForm(context, kind: PartyKind.supplier);
    if (id == null) return;
    final info = await ref.read(supplierRepositoryProvider).info(id);
    if (info != null) nav.pop(PickedSupplier(info.id, info.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(partyListProvider(
        (kind: PartyKind.supplier, query: _query, showHidden: false)));
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
                    child: Text(l10n.purchasePickSupplier,
                        style: GallaText.heading),
                  ),
                  TextButton(
                    onPressed: _addNew,
                    child: Text(l10n.purchaseNewSupplier,
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
                  ...list.maybeWhen(
                    data: (rows) => [
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: GallaCard(
                            onTap: () => Navigator.of(context)
                                .pop(PickedSupplier(r.id, r.name)),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                      color: GallaColors.chip,
                                      shape: BoxShape.circle),
                                  child: const Icon(
                                      Icons.local_shipping_outlined,
                                      color: GallaColors.ink),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(r.name,
                                      style: GallaText.display
                                          .copyWith(fontSize: 17),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
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
