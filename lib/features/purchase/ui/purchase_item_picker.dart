import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/current_shop.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/ui/item_thumb.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;

/// Search or scan an item to buy. Returns the chosen [Item].
Future<Item?> showPurchaseItemPicker(BuildContext context) {
  return showModalBottomSheet<Item>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ItemPicker(),
  );
}

class _ItemPicker extends ConsumerStatefulWidget {
  const _ItemPicker();

  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  String _query = '';

  Future<void> _scan() async {
    final l10n = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final code = await scanBarcode(context);
    if (code == null) return;
    final item = await ref
        .read(appDatabaseProvider)
        .inventoryDao
        .itemByBarcode(ref.read(shopIdProvider), code);
    if (item == null || item.isArchived) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.purchaseBarcodeUnknown)));
      return;
    }
    nav.pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(itemListProvider(
        (query: _query, lowOnly: false, showHidden: false)));
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
              child: Text(l10n.purchaseAddItemTitle, style: GallaText.heading),
            ),
            Padding(
              padding: const EdgeInsets.all(GallaSizes.screenPadding),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: l10n.inventorySearchHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: l10n.purchaseScan,
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
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
                            onTap: () => Navigator.of(context).pop(r.item),
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                ItemThumb(
                                    name: r.item.name,
                                    photoPath: r.item.photoPath,
 photoUrl: r.item.photoUrl),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(r.item.name,
                                          style: GallaText.display
                                              .copyWith(fontSize: 17),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                        '${formatPaisa(r.item.costPrice)}  ·  '
                                        '${formatQty(r.stock)} ${unitLabel(l10n, r.item.unit)}',
                                        style: GallaText.caption.copyWith(
                                            color: r.isLow
                                                ? GallaColors.danger
                                                : GallaColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.add_circle_outline,
                                    color: GallaColors.ink),
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
