import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart' show Item;
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;
import '../data/sales_repository.dart';
import '../domain/bill_controller.dart';
import '../domain/cart.dart';
import 'bill_scanner_page.dart';
import 'customer_picker_sheet.dart';
import 'discount_sheet.dart';
import 'item_pick_widgets.dart';
import 'number_entry_dialog.dart';
import 'stock_alert.dart';

/// Naya Bill: 3 taps for the common case (open Bill, tap item, Bill banao).
class BillScreen extends ConsumerStatefulWidget {
  const BillScreen({super.key});

  @override
  ConsumerState<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends ConsumerState<BillScreen> {
  final _paid = TextEditingController();
  String _query = '';
  bool _saving = false;

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ customer

  Future<bool> _pickCustomer() async {
    final picked = await showCustomerPicker(context);
    if (picked == null || !mounted) return false;
    ref.read(billProvider.notifier).setCustomer(picked.id, picked.name);
    if (picked.id == null) _paid.clear();
    return picked.id != null;
  }

  /// Udhaar needs a real customer: pick one first (Part 0 rule 5).
  Future<void> _chooseCredit(bool credit) async {
    final ctrl = ref.read(billProvider.notifier);
    if (!credit) {
      ctrl.setCredit(false);
      _paid.clear();
      return;
    }
    if (!ref.read(billProvider).hasRealCustomer) {
      final ok = await _pickCustomer();
      if (!ok) return;
    }
    ctrl.setCredit(true);
  }

  // ---------------------------------------------------------------- cart

  Future<void> _editQty(CartLine line) async {
    final l10n = AppLocalizations.of(context);
    final v = await askQuantity(context,
        title: l10n.qtyDialogTitle,
        current: line.qty,
        unit: unitLabel(l10n, line.unit));
    if (v == null || !mounted) return;
    final r = await ref.read(billProvider.notifier).setQtyChecked(line.itemId, v);
    if (!mounted || r.ok) return;
    await showStockAlert(context, ref, line.name, line.unit, r.available);
  }

  /// "+" on a cart row: one more unit, but never beyond the stock.
  Future<void> _plus(CartLine line) async {
    final r = await ref.read(billProvider.notifier).incrementChecked(line.itemId);
    if (!mounted || r.ok) return;
    await showStockAlert(context, ref, line.name, line.unit, r.available);
  }

  /// Adds one unit of [item] from a tap or search result. An item with no
  /// stock cannot be added at all.
  Future<void> _addItem(Item item) async {
    final r = await ref.read(billProvider.notifier).addItemChecked(item);
    if (!mounted || r.ok) return;
    await showStockAlert(context, ref, item.name, item.unit, r.available);
  }

  Future<void> _editPrice(CartLine line) async {
    final l10n = AppLocalizations.of(context);
    final v = await askPrice(context,
        title: l10n.priceDialogTitle, current: line.unitPrice);
    if (v != null) ref.read(billProvider.notifier).setPrice(line.itemId, v);
  }

  Future<void> _editDiscount(BillState s) async {
    final v = await showDiscountSheet(context,
        subtotal: s.subtotal, current: s.effectiveDiscount);
    if (v != null) ref.read(billProvider.notifier).setDiscount(v);
  }

  Future<void> _scan() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const BillScannerPage()),
    );
  }

  Future<void> _clearBill() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.billClearTitle, style: GallaText.heading),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.billClearYes)),
        ],
      ),
    );
    if (ok == true) {
      _paid.clear();
      await ref.read(billProvider.notifier).clear();
    }
  }

  // ---------------------------------------------------------------- save

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final ctrl = ref.read(billProvider.notifier);
    final repo = ref.read(salesRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final input = ctrl.toInput();
    if (input.lines.isEmpty) return;

    setState(() => _saving = true);
    try {
      // Nothing is sold beyond the stock on hand. The cart already refuses
      // such quantities; this catches stock that changed since (e.g. a
      // second phone sold the same item).
      final shortages = await repo.shortages(input.lines);
      if (shortages.isNotEmpty) {
        if (!mounted) return;
        await _showShortages(shortages);
        if (mounted) setState(() => _saving = false);
        return;
      }
      final saved = await repo.saveBill(input);
      await ctrl.clear();
      _paid.clear();
      ref.invalidate(quickPickProvider);
      if (!mounted) return;
      router.pushReplacement('/bill/done/${saved.saleId}');
    } on BillException catch (e) {
      if (kDebugMode) debugPrint('bill error: $e');
      final text = switch (e.error) {
        BillError.creditNeedsCustomer => l10n.billNeedCustomer,
        BillError.insufficientStock => l10n.stockNotEnoughSave,
        _ => l10n.billSaveFailed,
      };
      messenger.showSnackBar(SnackBar(content: Text(text)));
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (kDebugMode) debugPrint('save bill error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.billSaveFailed)));
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Save-time safety net: lists every line that is more than the stock.
  Future<void> _showShortages(List<StockShortage> shortages) {
    final l10n = AppLocalizations.of(context);
    final lines = ref.read(billProvider).lines;
    String unitFor(String id) {
      final u = lines.where((l) => l.itemId == id).firstOrNull?.unit ?? '';
      return u.isEmpty ? '' : ' ${unitLabel(l10n, u)}';
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: GallaColors.danger, size: 36),
        title: Text(l10n.stockNotEnoughTitle, style: GallaText.heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in shortages)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.stockLowLine(
                    s.name,
                    '${formatQty(s.available)}${unitFor(s.itemId)}',
                    '${formatQty(s.needed)}${unitFor(s.itemId)}',
                  ),
                  style: GallaText.body,
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.ok)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(billProvider);

    // When the saved draft finishes loading, show its "paid now" amount.
    ref.listen<BillState>(billProvider, (prev, next) {
      if ((prev == null || !prev.loaded) && next.loaded && next.paidNow > 0) {
        _paid.text = formatPaisaPlain(next.paidNow);
      }
    });

    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(l10n, s),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 16),
                children: [
                  _searchRow(l10n),
                  const SizedBox(height: 10),
                  if (searching)
                    ..._searchResults(s)
                  else
                    _quickGrid(l10n),
                  const SizedBox(height: 12),
                  if (s.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(l10n.billEmptyCart,
                            style: GallaText.body
                                .copyWith(color: GallaColors.muted)),
                      ),
                    )
                  else ...[
                    for (final line in s.lines) _cartRow(l10n, line),
                    const SizedBox(height: 8),
                    _discountRow(l10n, s),
                    const SizedBox(height: 12),
                    _paymentPanel(l10n, s),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding, 8,
                  GallaSizes.screenPadding, 12),
              child: GallaPrimaryButton(
                height: 64,
                label: l10n.billMake,
                trailing: formatPaisa(s.total),
                onPressed: (s.isEmpty || _saving || !s.loaded) ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n, BillState s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          GallaSizes.screenPadding, 12, GallaSizes.screenPadding, 8),
      child: Row(
        children: [
          const GallaBackButton(),
          const SizedBox(width: 12),
          Flexible(
            child: GallaChip(
              label: s.customerName ?? l10n.billNaqadCustomer,
              icon: Icons.person_outline,
              tone: s.hasRealCustomer
                  ? GallaChipTone.selected
                  : GallaChipTone.normal,
              onTap: _pickCustomer,
            ),
          ),
          const Spacer(),
          if (!s.isEmpty)
            IconButton(
              tooltip: l10n.billClearTitle,
              onPressed: _clearBill,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }

  Widget _searchRow(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.billSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          height: 56,
          child: Material(
            color: GallaColors.ink,
            borderRadius: GallaRadius.card,
            child: InkWell(
              borderRadius: GallaRadius.card,
              onTap: _scan,
              child: const Icon(Icons.qr_code_scanner,
                  color: GallaColors.lime, size: 28),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _searchResults(BillState s) {
    final results = ref.watch(
        itemListProvider((query: _query, lowOnly: false, showHidden: false)));
    final qtyInCart = {for (final l in s.lines) l.itemId: l.qty};
    return results.maybeWhen(
      data: (list) => [
        for (final e in list.take(30))
          ItemPickRow(
            entry: e,
            inCart: qtyInCart[e.item.id] ?? 0,
            onTap: () {
              _addItem(e.item);
              // Back to the grid so the next item is one tap away.
              FocusScope.of(context).unfocus();
              setState(() => _query = '');
            },
          ),
      ],
      orElse: () => const <Widget>[],
    );
  }

  Widget _quickGrid(AppLocalizations l10n) {
    final picks = ref.watch(quickPickProvider).valueOrNull ?? const [];
    // 8 most-sold + the "Sab dekho" tile = 9 tiles in 3 columns.
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: [
        for (final item in picks)
          QuickPickTile(
            item: item,
            onTap: () => _addItem(item),
          ),
        SeeAllTile(
          label: l10n.billQuickAll,
          onTap: () => showAllItemsSheet(context),
        ),
      ],
    );
  }

  Widget _cartRow(AppLocalizations l10n, CartLine line) {
    final ctrl = ref.read(billProvider.notifier);
    final unit = unitLabel(l10n, line.unit);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GallaCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(line.name,
                      style: GallaText.display.copyWith(fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                MoneyText(line.total, size: 17),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Tap the price: override for this bill only.
                InkWell(
                  onTap: () => _editPrice(line),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: GallaSizes.touch),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      child: Text(
                        l10n.billLineDetail(
                          formatPaisaPlain(line.unitPrice),
                          formatQty(line.qty),
                          unit,
                        ),
                        style: GallaText.caption.copyWith(
                          color: line.isOverridden
                              ? GallaColors.udhaar
                              : GallaColors.muted,
                          fontWeight: line.isOverridden
                              ? FontWeight.w700
                              : FontWeight.w400,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _StepButton(
                  icon: Icons.remove,
                  onTap: () => ctrl.decrement(line.itemId),
                ),
                // Tap the quantity: number pad (2.5 kg).
                InkWell(
                  onTap: () => _editQty(line),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        minWidth: 52, minHeight: GallaSizes.touch),
                    child: Center(
                      child: Text(formatQty(line.qty),
                          style: GallaText.display.copyWith(fontSize: 20)),
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add,
                  onTap: () => _plus(line),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _discountRow(AppLocalizations l10n, BillState s) {
    final d = s.effectiveDiscount;
    return GallaCard(
      onTap: () => _editDiscount(s),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.sell_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(l10n.billDiscount, style: GallaText.bodyMedium)),
          if (d > 0)
            Text('- ${formatPaisa(d)}',
                style: GallaText.display
                    .copyWith(fontSize: 17, color: GallaColors.received))
          else
            const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _paymentPanel(AppLocalizations l10n, BillState s) {
    final pay = s.payment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ModeButton(
                label: l10n.billCash,
                selected: !s.credit,
                onTap: () => _chooseCredit(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeButton(
                label: l10n.billUdhaar,
                selected: s.credit,
                onTap: () => _chooseCredit(true),
              ),
            ),
          ],
        ),
        if (s.credit) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _paid,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: GallaText.display.copyWith(fontSize: 20),
            decoration: InputDecoration(
              labelText: l10n.billPaidNow,
              prefixText: 'Rs ',
            ),
            onChanged: (v) => ref
                .read(billProvider.notifier)
                .setPaidNow(v.trim().isEmpty ? 0 : (parseRupeesToPaisa(v) ?? 0)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              l10n.billKhataRemaining(formatPaisa(pay.unpaid)),
              style: GallaText.display
                  .copyWith(fontSize: 16, color: GallaColors.udhaar),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: GallaSizes.touch,
      height: GallaSizes.touch,
      child: Material(
        color: GallaColors.chip,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, color: GallaColors.ink),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? GallaColors.ink : GallaColors.chip,
      borderRadius: GallaRadius.card,
      child: InkWell(
        borderRadius: GallaRadius.card,
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              label,
              style: GallaText.display.copyWith(
                fontSize: 18,
                color: selected ? GallaColors.lime : GallaColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
