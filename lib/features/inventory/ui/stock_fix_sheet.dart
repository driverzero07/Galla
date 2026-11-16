import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../l10n/gen/app_localizations.dart';

/// New stock count + reason, for correcting stock after a recount.
class StockFixResult {
  const StockFixResult(this.newCount, this.reason);
  final int newCount; // thousandths
  final String reason;
}

Future<StockFixResult?> showStockFixSheet(
  BuildContext context, {
  required int currentStock,
}) {
  return showModalBottomSheet<StockFixResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StockFixSheet(currentStock: currentStock),
  );
}

class _StockFixSheet extends StatefulWidget {
  const _StockFixSheet({required this.currentStock});

  final int currentStock;

  @override
  State<_StockFixSheet> createState() => _StockFixSheetState();
}

class _StockFixSheetState extends State<_StockFixSheet> {
  late final _count =
      TextEditingController(text: formatQtyPlain(widget.currentStock));
  final _reason = TextEditingController();
  String? _countError;
  String? _reasonError;

  @override
  void dispose() {
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final milli = parseQtyToMilli(_count.text);
    final reason = _reason.text.trim();
    setState(() {
      _countError = milli == null ? l10n.itemInvalidNumber : null;
      _reasonError = reason.isEmpty ? l10n.stockFixReasonRequired : null;
    });
    if (milli == null || reason.isEmpty) return;
    Navigator.of(context).pop(StockFixResult(milli, reason));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          Text(l10n.itemFixStock, style: GallaText.heading),
          const SizedBox(height: 16),
          TextField(
            controller: _count,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: GallaText.display.copyWith(fontSize: 22),
            decoration: InputDecoration(
              labelText: l10n.stockFixNewCount,
              errorText: _countError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.stockFixReason,
              errorText: _reasonError,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          GallaPrimaryButton(label: l10n.save, onPressed: _submit),
        ],
      ),
    );
  }
}
