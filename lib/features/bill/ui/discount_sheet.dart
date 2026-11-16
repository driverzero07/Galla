import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_chip.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/bill_math.dart';

/// Discount amount + round-off buttons (nearest Rs 10 / 50 / 100). Resolves
/// to the new discount in paisa (0 clears it), or null if dismissed.
Future<int?> showDiscountSheet(
  BuildContext context, {
  required int subtotal,
  required int current,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DiscountSheet(subtotal: subtotal, current: current),
  );
}

class _DiscountSheet extends StatefulWidget {
  const _DiscountSheet({required this.subtotal, required this.current});

  final int subtotal;
  final int current;

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  late final _controller = TextEditingController(
      text: widget.current > 0 ? formatPaisaPlain(widget.current) : '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value =>
      _controller.text.trim().isEmpty ? 0 : parseRupeesToPaisa(_controller.text);

  void _roundOff(int stepRupees) {
    final d = roundOffDiscount(widget.subtotal, stepRupees * 100);
    setState(() {
      _controller.text = d > 0 ? formatPaisaPlain(d) : '';
      _error = null;
    });
  }

  void _apply() {
    final l10n = AppLocalizations.of(context);
    final v = _value;
    if (v == null) {
      setState(() => _error = l10n.itemInvalidNumber);
    } else if (v > widget.subtotal) {
      setState(() => _error = l10n.billDiscountMax);
    } else {
      Navigator.of(context).pop(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = _value;
    final preview = (value != null && value <= widget.subtotal)
        ? widget.subtotal - value
        : widget.subtotal;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GallaSizes.screenPadding,
        0,
        GallaSizes.screenPadding,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.billDiscountTitle, style: GallaText.heading),
          const SizedBox(height: 4),
          Text(formatPaisa(widget.subtotal), style: GallaText.caption),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: GallaText.display.copyWith(fontSize: 26),
            decoration: InputDecoration(
              labelText: l10n.billDiscountAmount,
              prefixText: 'Rs ',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: 12),
          Text(l10n.billRoundOff, style: GallaText.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final step in const [10, 50, 100])
                GallaChip(
                  label: l10n.billRoundTo(step),
                  // Nothing to round off when the bill is smaller than a step.
                  onTap: widget.subtotal >= step * 100
                      ? () => _roundOff(step)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('${l10n.purchaseTotal}: ${formatPaisa(preview)}',
              style: GallaText.display.copyWith(fontSize: 18)),
          const SizedBox(height: 12),
          GallaPrimaryButton(label: l10n.billDiscountApply, onPressed: _apply),
          const SizedBox(height: 8),
          GallaOutlineButton(
            label: l10n.billDiscountClear,
            onPressed: () => Navigator.of(context).pop(0),
          ),
        ],
      ),
    );
  }
}
