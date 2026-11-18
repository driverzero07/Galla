import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bill/ui/number_entry_dialog.dart';
import '../../customers/data/party_repository.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../data/purchase_repository.dart';
import '../domain/purchase_controller.dart';
import '../../khata/data/khata_repository.dart';
import 'purchase_item_picker.dart';
import 'purchase_line_dialog.dart';
import 'supplier_picker_sheet.dart';

/// Naya Purchase (tab): invoice photo, supplier, items with cost, totals.
class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key, this.initialSupplierId});

  /// From "Naya Purchase" on a supplier's khata.
  final String? initialSupplierId;

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _applyInitialSupplier();
  }

  @override
  void didUpdateWidget(covariant PurchaseScreen old) {
    super.didUpdateWidget(old);
    if (old.initialSupplierId != widget.initialSupplierId) {
      _applyInitialSupplier();
    }
  }

  void _applyInitialSupplier() {
    final id = widget.initialSupplierId;
    if (id == null) return;
    Future.microtask(() async {
      final info = await ref.read(supplierRepositoryProvider).info(id);
      if (info != null && mounted) {
        ref.read(purchaseControllerProvider.notifier).setSupplier(info.id, info.name);
      }
    });
  }

  Future<void> _photo() async {
    try {
      final path = await ref.read(photoServiceProvider).takePhoto();
      if (path != null) {
        ref.read(purchaseControllerProvider.notifier).setInvoice(path);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('invoice photo error: $e');
    }
  }

  Future<void> _pickSupplier() async {
    final s = await showSupplierPicker(context);
    if (s != null) {
      ref.read(purchaseControllerProvider.notifier).setSupplier(s.id, s.name);
    }
  }

  Future<void> _addItem() async {
    final item = await showPurchaseItemPicker(context);
    if (item == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final existing = ref
        .read(purchaseControllerProvider)
        .lines
        .where((l) => l.itemId == item.id)
        .firstOrNull;
    final v = await showPurchaseLineDialog(
      context,
      name: item.name,
      unit: unitLabel(l10n, item.unit),
      qty: existing?.qty ?? 1000,
      cost: existing?.unitCost ?? item.costPrice,
    );
    if (v == null) return;
    final c = ref.read(purchaseControllerProvider.notifier);
    c.addItem(item, qty: existing == null ? v.qty : 0);
    c.setQty(item.id, v.qty);
    c.setCost(item.id, v.cost);
  }

  Future<void> _editLine(PurchaseLineState line) async {
    final l10n = AppLocalizations.of(context);
    final v = await showPurchaseLineDialog(
      context,
      name: line.name,
      unit: unitLabel(l10n, line.unit),
      qty: line.qty,
      cost: line.unitCost,
    );
    if (v == null) return;
    final c = ref.read(purchaseControllerProvider.notifier);
    c.setQty(line.itemId, v.qty);
    c.setCost(line.itemId, v.cost);
  }

  Future<void> _editPaid(PurchaseDraft d) async {
    final l10n = AppLocalizations.of(context);
    final v = await askPrice(context,
        title: l10n.purchasePaidNow, current: d.paidNow);
    if (v != null) {
      ref.read(purchaseControllerProvider.notifier).setPaidNow(v);
    }
  }

  Future<void> _save(PurchaseDraft d) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (d.supplierId == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.purchaseNeedSupplier)));
      return;
    }
    if (d.lines.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.purchaseNeedItems)));
      return;
    }
    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(purchaseRepositoryProvider).savePurchase(d.toInput());
      ref.read(purchaseControllerProvider.notifier).clear();
      messenger.showSnackBar(SnackBar(content: Text(l10n.purchaseSaved)));
      router.push('/purchases/${saved.purchaseId}');
    } on PurchaseException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.error == PurchaseError.insufficientCash
              ? l10n.cashNotEnough(formatPaisa(e.available))
              : l10n.purchaseSaveFailed)));
    } catch (e) {
      if (kDebugMode) debugPrint('purchase save error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.purchaseSaveFailed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = ref.watch(purchaseControllerProvider);
    final c = ref.read(purchaseControllerProvider.notifier);

    // Supplier's whole balance after this purchase (derived, never typed).
    final current = d.supplierId == null
        ? 0
        : (ref.watch(supplierHistoryProvider(d.supplierId!)).valueOrNull
                ?.balance ??
            0);
    final after = current + d.unpaid;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          GallaHeader(
            title: l10n.purchaseNewTitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!d.isEmpty)
                  IconButton(
                    tooltip: l10n.purchaseClear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: c.clear,
                  ),
                IconButton(
                  tooltip: l10n.purchaseHistory,
                  icon: const Icon(Icons.history),
                  onPressed: () => context.push('/purchases'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 12),
              children: [
                _PhotoTile(path: d.invoicePath, onTap: _photo),
                const SizedBox(height: 10),
                GallaCard(
                  onTap: _pickSupplier,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            color: GallaColors.chip, shape: BoxShape.circle),
                        child: Text(
                          (d.supplierName ?? '?').trim().isEmpty
                              ? '?'
                              : (d.supplierName ?? '?').trim()[0].toUpperCase(),
                          style: GallaText.display.copyWith(fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.purchaseSupplier,
                                style: GallaText.caption),
                            Text(d.supplierName ?? l10n.purchasePickSupplier,
                                style: GallaText.display.copyWith(
                                    fontSize: 18,
                                    color: d.supplierName == null
                                        ? GallaColors.muted
                                        : GallaColors.ink)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.purchaseItems, style: GallaText.heading),
                const SizedBox(height: 4),
                for (final line in d.lines)
                  _LineTile(
                    line: line,
                    onTap: () => _editLine(line),
                    onRemove: () => c.remove(line.itemId),
                  ),
                const SizedBox(height: 8),
                GallaOutlineButton(
                  dashed: true,
                  label: l10n.purchaseAddItem,
                  onPressed: _addItem,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding, 4,
                GallaSizes.screenPadding, 8),
            child: Column(
              children: [
                GallaCard(
                  hero: true,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _TotalRow(
                          label: l10n.purchaseTotal,
                          paisa: d.total,
                          tone: MoneyTone.onDark),
                      InkWell(
                        onTap: () => _editPaid(d),
                        child: _TotalRow(
                            label: l10n.purchasePaidNow,
                            paisa: d.effectivePaid,
                            tone: MoneyTone.onDark,
                            editable: true),
                      ),
                      _TotalRow(
                          label: l10n.purchaseSupplierBalance,
                          paisa: after,
                          tone: MoneyTone.onDark,
                          big: true),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                GallaPrimaryButton(
                  lime: true,
                  height: 60,
                  label: l10n.purchaseSave,
                  onPressed: _saving ? null : () => _save(d),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.paisa,
    required this.tone,
    this.big = false,
    this.editable = false,
  });

  final String label;
  final int paisa;
  final MoneyTone tone;
  final bool big;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: GallaSizes.touch - 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GallaText.body.copyWith(color: GallaColors.chip)),
          ),
          if (editable)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.edit, size: 16, color: GallaColors.chip),
            ),
          MoneyText(paisa, size: big ? 22 : 18, tone: MoneyTone.onDark),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.onTap,
    required this.onRemove,
  });

  final PurchaseLineState line;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name,
                      style: GallaText.display.copyWith(fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    l10n.purchaseCostLine(formatPaisaPlain(line.unitCost),
                        formatQty(line.qty), unitLabel(l10n, line.unit)),
                    style: GallaText.caption,
                  ),
                ],
              ),
            ),
            MoneyText(line.total, size: 18, symbol: false),
            IconButton(
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close, size: 20),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.path, required this.onTap});

  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (path == null) {
      return GallaOutlineButton(
        dashed: true,
        height: 72,
        icon: Icons.photo_camera_outlined,
        label: l10n.purchaseInvoicePhoto,
        onPressed: onTap,
      );
    }
    return GallaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: GallaRadius.thumbnail,
            child: Image.file(File(path!),
                width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l10n.purchaseChangePhoto,
                style: GallaText.bodyMedium.copyWith(color: GallaColors.ink)),
          ),
          const Icon(Icons.check_circle, color: GallaColors.received),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
