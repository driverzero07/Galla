import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/daos/purchases_dao.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../khata/ui/history_widgets.dart';
import '../data/purchase_repository.dart';

/// Every purchase, newest first.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(purchaseListProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(title: l10n.purchaseHistory, showBack: true),
            Expanded(
              child: list.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) {
                  if (rows.isEmpty) {
                    return EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      message: l10n.purchaseHistoryEmpty,
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding,
                        4, GallaSizes.screenPadding, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _Tile(row: rows[i]),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.row});

  final PurchaseListRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = row.purchase;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        onTap: () => context.push('/purchases/${p.id}'),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.purchaseNo.isEmpty
                        ? l10n.purchaseDetailTitleNoNo
                        : l10n.supplierPurchaseNo(p.purchaseNo),
                    style: GallaText.display.copyWith(fontSize: 17),
                  ),
                  Text(
                    '${whenText(l10n, DateTime.now(), p.createdAt)}  ·  '
                    '${row.supplierName}',
                    style: GallaText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (p.invoiceImagePath != null || p.invoiceImageUrl != null)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.photo_camera_outlined,
                    size: 18, color: GallaColors.muted),
              ),
            MoneyText(p.total, size: 17),
          ],
        ),
      ),
    );
  }
}
