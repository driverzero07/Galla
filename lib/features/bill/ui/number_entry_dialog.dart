import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Number pad dialog (decimals allowed, e.g. 2.5 kg). Returns the parsed
/// value, or null if cancelled.
Future<int?> showNumberDialog(
  BuildContext context, {
  required String title,
  required String initialText,
  required int? Function(String text) parse,
  String? prefix,
  String? suffix,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _NumberDialog(
      title: title,
      initialText: initialText,
      parse: parse,
      prefix: prefix,
      suffix: suffix,
    ),
  );
}

/// Quantity in thousandths. Zero is allowed (it removes the row).
Future<int?> askQuantity(BuildContext context,
    {required String title, required int current, required String unit}) {
  return showNumberDialog(
    context,
    title: title,
    initialText: formatQtyPlain(current),
    parse: (t) => t.trim().isEmpty ? 0 : parseQtyToMilli(t),
    suffix: unit,
  );
}

/// Price in paisa for this bill only.
Future<int?> askPrice(BuildContext context,
    {required String title, required int current}) {
  return showNumberDialog(
    context,
    title: title,
    initialText: formatPaisaPlain(current),
    parse: (t) => t.trim().isEmpty ? 0 : parseRupeesToPaisa(t),
    prefix: 'Rs ',
  );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.initialText,
    required this.parse,
    this.prefix,
    this.suffix,
  });

  final String title;
  final String initialText;
  final int? Function(String) parse;
  final String? prefix;
  final String? suffix;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select everything so typing replaces the old value.
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initialText.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = widget.parse(_controller.text);
    if (value == null) {
      setState(() => _error = AppLocalizations.of(context).itemInvalidNumber);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title, style: GallaText.heading),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: GallaText.display.copyWith(fontSize: 28),
        decoration: InputDecoration(
          prefixText: widget.prefix,
          suffixText: widget.suffix,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.ok)),
      ],
    );
  }
}
