import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/import_numbers.dart';
import '../domain/migration_controller.dart';

class _QuickRow {
  final name = TextEditingController();
  final amount = TextEditingController();
  final nameFocus = FocusNode();
  final amountFocus = FocusNode();

  void dispose() {
    name.dispose();
    amount.dispose();
    nameFocus.dispose();
    amountFocus.dispose();
  }
}

/// Keyboard-only entry: name, Done, amount, Done, next line. Blank lines
/// are ignored.
class QuickEntryStep extends ConsumerStatefulWidget {
  const QuickEntryStep({super.key});

  @override
  ConsumerState<QuickEntryStep> createState() => _QuickEntryStepState();
}

class _QuickEntryStepState extends ConsumerState<QuickEntryStep> {
  final _rows = <_QuickRow>[_QuickRow(), _QuickRow(), _QuickRow()];
  final _scroll = ScrollController();

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _addRowAndFocus() {
    final row = _QuickRow();
    setState(() => _rows.add(row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      row.nameFocus.requestFocus();
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
  }

  void _amountDone(int index) {
    if (index == _rows.length - 1) {
      _addRowAndFocus();
    } else {
      _rows[index + 1].nameFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    var count = 0;
    var total = 0;
    for (final r in _rows) {
      if (r.name.text.trim().isEmpty) continue;
      count++;
      final a = parseImportAmount(r.amount.text);
      if (!a.error) total += a.paisa;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: GallaSizes.screenPadding, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.migrationQuickHint,
                style: GallaText.body.copyWith(color: GallaColors.muted)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(
                horizontal: GallaSizes.screenPadding, vertical: 8),
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final r = _rows[i];
              return Padding(
                key: ObjectKey(r),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: r.name,
                        focusNode: r.nameFocus,
                        autofocus: i == 0,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        onEditingComplete: () => r.amountFocus.requestFocus(),
                        decoration:
                            InputDecoration(labelText: l10n.migrationName),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: r.amount,
                        focusNode: r.amountFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,?\-\u0660-\u0669\u06F0-\u06F9]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        onEditingComplete: () => _amountDone(i),
                        decoration:
                            InputDecoration(labelText: l10n.migrationAmount),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding, 4,
              GallaSizes.screenPadding, GallaSizes.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.migrationQuickCount(count, formatPaisa(total)),
                style: GallaText.bodyMedium,
              ),
              const SizedBox(height: 8),
              GallaPrimaryButton(
                label: l10n.migrationNext,
                onPressed: count == 0
                    ? null
                    : () => ref
                        .read(migrationControllerProvider.notifier)
                        .finishQuick([
                      for (final r in _rows)
                        (name: r.name.text, amount: r.amount.text),
                    ]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
