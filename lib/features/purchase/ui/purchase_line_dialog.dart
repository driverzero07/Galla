import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Quantity (thousandths) and unit cost (paisa) of one purchase line.
typedef LineValues = ({int qty, int cost});

/// Asks the quantity that came in and what it cost per unit.
Future<LineValues?> showPurchaseLineDialog(
  BuildContext context, {
  required String name,
  required String unit,
  required int qty,
  required int cost,
}) {
  return showDialog<LineValues>(
    context: context,
    builder: (_) =>
        _LineDialog(name: name, unit: unit, qty: qty, cost: cost),
  );
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({
    required this.name,
    required this.unit,
    required this.qty,
    required this.cost,
  });

  final String name;
  final String unit;
  final int qty;
  final int cost;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _qty = TextEditingController(text: formatQtyPlain(widget.qty));
  late final _cost = TextEditingController(
      text: widget.cost == 0 ? '' : formatPaisaPlain(widget.cost));
  bool _invalid = false;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _ok() {
    final q = parseQtyToMilli(_qty.text);
    final c = _cost.text.trim().isEmpty ? 0 : parseRupeesToPaisa(_cost.text);
    if (q == null || q <= 0 || c == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, (qty: q, cost: c));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Text(widget.name,
          style: GallaText.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: keyboard,
            decoration: InputDecoration(
              labelText: l10n.purchaseQtyTitle,
              suffixText: widget.unit,
              errorText: _invalid ? l10n.entryAmountInvalid : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cost,
            keyboardType: keyboard,
            decoration: InputDecoration(
              labelText: l10n.purchaseCostTitle,
              prefixText: 'Rs ',
            ),
            onSubmitted: (_) => _ok(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _ok, child: Text(l10n.ok)),
      ],
    );
  }
}
