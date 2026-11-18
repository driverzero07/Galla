import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/inventory_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/ui/item_thumb.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../domain/bill_controller.dart';
import 'stock_alert.dart';

/// Tile in the quick-pick grid: tap once = one unit added to the bill.
class QuickPickTile extends StatelessWidget {
  const QuickPickTile({super.key, required this.item, required this.onTap});

  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GallaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ItemThumb(name: item.name, photoPath: item.photoPath,
 photoUrl: item.photoUrl, size: 40),
          const SizedBox(height: 6),
          Text(
            item.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GallaText.display.copyWith(fontSize: 14, height: 1.1),
          ),
          const SizedBox(height: 2),
          Text(formatPaisa(item.salePrice), style: GallaText.caption),
        ],
      ),
    );
  }
}

/// "Sab dekho" tile at the end of the grid.
class SeeAllTile extends StatelessWidget {
  const SeeAllTile({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GallaColors.ink,
      borderRadius: GallaRadius.card,
      child: InkWell(
        borderRadius: GallaRadius.card,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apps, color: GallaColors.lime),
              const SizedBox(height: 4),
              Text(label,
                  style: GallaText.display
                      .copyWith(fontSize: 14, color: GallaColors.lime)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row in search results / "Sab dekho". Shows how many are already in the
/// bill. Stock is shown so the shopkeeper sees "kam hai" before selling.
class ItemPickRow extends StatelessWidget {
  const ItemPickRow({
    super.key,
    required this.entry,
    required this.inCart,
    required this.onTap,
  });

  final ItemWithStock entry;
  final int inCart; // thousandths
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = entry.item;
    final unit = unitLabel(l10n, item.unit);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GallaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ItemThumb(name: item.name, photoPath: item.photoPath,
 photoUrl: item.photoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: GallaText.display.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${formatPaisa(item.salePrice)} / $unit  ·  '
                    '${formatQty(entry.stock)} $unit',
                    style: GallaText.caption.copyWith(
                        color: entry.isLow
                            ? GallaColors.danger
                            : GallaColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (inCart > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GallaColors.ink,
                  borderRadius: BorderRadius.circular(GallaRadius.round),
                ),
                child: Text(formatQty(inCart),
                    style: GallaText.display
                        .copyWith(fontSize: 14, color: GallaColors.lime)),
              )
            else
              const Icon(Icons.add_circle_outline, color: GallaColors.ink),
          ],
        ),
      ),
    );
  }
}

/// "Sab dekho": every visible item with search; tapping adds one unit and
/// the sheet stays open so several items can be added.
Future<void> showAllItemsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AllItemsSheet(),
  );
}

class _AllItemsSheet extends ConsumerStatefulWidget {
  const _AllItemsSheet();

  @override
  ConsumerState<_AllItemsSheet> createState() => _AllItemsSheetState();
}

class _AllItemsSheetState extends ConsumerState<_AllItemsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(
        itemListProvider((query: _query, lowOnly: false, showHidden: false)));
    final cart = ref.watch(billProvider);
    final qtyInCart = {for (final l in cart.lines) l.itemId: l.qty};
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.billAllItemsTitle, style: GallaText.heading),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GallaSizes.screenPadding),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l10n.billSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: items.maybeWhen(
                data: (list) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: GallaSizes.screenPadding),
                  itemCount: list.length,
                  itemBuilder: (context, i) => ItemPickRow(
                    entry: list[i],
                    inCart: qtyInCart[list[i].item.id] ?? 0,
                    onTap: () => _addChecked(context, ref, list[i].item),
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds one unit, or tells the shopkeeper why it cannot be added.
Future<void> _addChecked(BuildContext context, WidgetRef ref, Item item) async {
  final r = await ref.read(billProvider.notifier).addItemChecked(item);
  if (r.ok || !context.mounted) return;
  await showStockAlert(context, ref, item.name, item.unit, r.available);
}
