import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/daos/inventory_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/inventory_repository.dart';
import 'item_thumb.dart';

/// Saman (inventory) list: search, "Khatam hone wala" filter, hidden toggle.
class SamanScreen extends ConsumerStatefulWidget {
  const SamanScreen({super.key, this.initialLowOnly = false});

  /// Opened from Home's "..." or the bell: start on the low-stock filter.
  final bool initialLowOnly;

  @override
  ConsumerState<SamanScreen> createState() => _SamanScreenState();
}

class _SamanScreenState extends ConsumerState<SamanScreen> {
  String _query = '';
  late bool _lowOnly = widget.initialLowOnly;
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = (query: _query, lowOnly: _lowOnly, showHidden: _showHidden);
    final items = ref.watch(itemListProvider(q));
    final lowCount = ref.watch(lowStockCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(
              title: l10n.inventoryTitle,
              showBack: true,
              trailing: GallaPillButton(
                label: l10n.inventoryAdd,
                onPressed: () => context.push('/saman/add'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: GallaSizes.screenPadding, vertical: 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.inventorySearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: GallaSizes.screenPadding, vertical: 4),
                children: [
                  GallaChip(
                    label: l10n.inventoryFilterAll,
                    tone: _lowOnly
                        ? GallaChipTone.normal
                        : GallaChipTone.selected,
                    onTap: () => setState(() => _lowOnly = false),
                  ),
                  const SizedBox(width: 8),
                  GallaChip(
                    label: l10n.inventoryFilterLow(lowCount),
                    tone: _lowOnly
                        ? GallaChipTone.selected
                        : GallaChipTone.danger,
                    onTap: () => setState(() => _lowOnly = true),
                  ),
                  const SizedBox(width: 8),
                  GallaChip(
                    label: l10n.inventoryShowHidden,
                    icon: _showHidden
                        ? Icons.visibility
                        : Icons.visibility_off_outlined,
                    tone: _showHidden
                        ? GallaChipTone.selected
                        : GallaChipTone.normal,
                    onTap: () => setState(() => _showHidden = !_showHidden),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) {
                  if (list.isEmpty) {
                    final searching = _query.trim().isNotEmpty || _lowOnly;
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: searching
                          ? l10n.inventoryNoMatch
                          : l10n.inventoryEmpty,
                      actionLabel: searching ? null : l10n.inventoryAdd,
                      onAction: () => context.push('/saman/add'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 24),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _ItemRow(entry: list[i]),
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.entry});

  final ItemWithStock entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = entry.item;
    final low = entry.isLow && !item.isArchived;
    final unit = _unitLabel(l10n, item.unit);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: item.isArchived ? 0.55 : 1,
        child: GallaCard(
          color: low ? GallaColors.dangerBg : null,
          border: low ? Border.all(color: GallaColors.dangerBorder) : null,
          padding: const EdgeInsets.all(12),
          onTap: () => context.push('/saman/add?id=${item.id}'),
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
                        style: GallaText.display.copyWith(fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      l10n.inventorySellCostLine(
                        formatPaisa(item.salePrice, symbol: false),
                        formatPaisa(item.costPrice, symbol: false),
                      ),
                      style: GallaText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatQty(entry.stock)} $unit',
                    style: GallaText.display.copyWith(
                      fontSize: 16,
                      color: low ? GallaColors.danger : GallaColors.ink,
                    ),
                  ),
                  if (item.isArchived)
                    Text(l10n.itemHiddenTag, style: GallaText.label)
                  else if (low)
                    Text(
                      l10n.inventoryLowBadge,
                      style: GallaText.label.copyWith(
                          color: GallaColors.danger,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lower-case unit word for stock text ("5 kg").
String _unitLabel(AppLocalizations l10n, String unit) => switch (unit) {
      'kg' => l10n.unitKg.toLowerCase(),
      'pack' => l10n.unitPack.toLowerCase(),
      'dozen' => l10n.unitDozen.toLowerCase(),
      _ => l10n.unitPiece.toLowerCase(),
    };

String unitLabel(AppLocalizations l10n, String unit) =>
    _unitLabel(l10n, unit);
