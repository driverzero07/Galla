import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/constants.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/import_rows.dart';
import '../domain/migration_controller.dart';

/// Step 2: every line can be fixed here before anything is saved.
class ConfirmStep extends ConsumerStatefulWidget {
  const ConfirmStep({super.key});

  @override
  ConsumerState<ConfirmStep> createState() => _ConfirmStepState();
}

class _ConfirmStepState extends ConsumerState<ConfirmStep> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final left = ctrl.uncertainLeft;
    if (left > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.migrationUncertainTitle),
          content: Text(l10n.migrationUncertainBody(left)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.migrationCheckAgain)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.migrationGoAhead)),
          ],
        ),
      );
      if (go != true) return;
    }
    await ctrl.commit();
  }

  void _addRow() {
    ref.read(migrationControllerProvider.notifier).addPartyRow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(migrationControllerProvider);
    final ctrl = ref.read(migrationControllerProvider.notifier);

    final errors = ctrl.blockingErrors;
    final canSave = errors == 0 && ctrl.willImport > 0 && !s.busy;
    final count = s.isItems ? s.itemRows.length : s.partyRows.length;

    final source = switch (s.method) {
      ImportMethod.file => s.fileName,
      ImportMethod.ocr => l10n.migrationPage(1),
      _ => l10n.migrationSourceQuick,
    };

    final partyA = s.isItems ? const <PartyAssessment>[] : s.partyAssessments;
    final itemA = s.isItems ? s.itemAssessments : const <ItemAssessment>[];

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(
                horizontal: GallaSizes.screenPadding, vertical: 4),
            children: [
              GallaCard(
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EBDD),
                        borderRadius: BorderRadius.circular(GallaRadius.thumb),
                        border: Border.all(color: const Color(0xFFD9D0BC)),
                      ),
                      child: const Icon(Icons.notes,
                          color: Color(0xFFB5AC97), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GallaText.heading.copyWith(fontSize: 17)),
                          const SizedBox(height: 2),
                          Text(
                            s.isItems
                                ? l10n.migrationFoundItems(count)
                                : l10n.migrationFound(count),
                            style: GallaText.caption
                                .copyWith(color: GallaColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!s.isItems)
                for (var i = 0; i < s.partyRows.length; i++)
                  _PartyTile(
                    key: ValueKey('p${s.partyRows[i].id}'),
                    row: s.partyRows[i],
                    assessment: partyA[i],
                  )
              else
                for (var i = 0; i < s.itemRows.length; i++)
                  _ItemTile(
                    key: ValueKey('i${s.itemRows[i].id}'),
                    row: s.itemRows[i],
                    assessment: itemA[i],
                  ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding, 8,
              GallaSizes.screenPadding, GallaSizes.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!s.isItems) ...[
                GallaOutlineButton(
                  label: l10n.migrationManual,
                  onPressed: _addRow,
                  height: 52,
                ),
                const SizedBox(height: 10),
              ],
              GallaPrimaryButton(
                label: errors > 0
                    ? l10n.migrationFixLines(errors)
                    : l10n.migrationConfirmAll,
                onPressed: canSave ? _confirm : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- shared

BoxDecoration _tileDecoration(Set<RowIssue> issues, bool include) {
  final isError = issues.contains(RowIssue.error);
  final isUncertain = issues.contains(RowIssue.uncertain);
  Color color = GallaColors.card;
  Border? border;
  if (isError) {
    color = GallaColors.dangerBg;
    border = Border.all(color: GallaColors.danger, width: 1.5);
  } else if (isUncertain && include) {
    color = GallaColors.warningBg;
    border = Border.all(color: GallaColors.warningBorder, width: 1.5);
  }
  return BoxDecoration(
    color: color,
    border: border,
    borderRadius: BorderRadius.circular(GallaRadius.base),
    boxShadow: GallaShadows.card,
  );
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.issues, required this.include});
  final Set<RowIssue> issues;
  final bool include;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String text = l10n.migrationName;
    Color color = GallaColors.muted;
    if (issues.contains(RowIssue.error)) {
      text = l10n.migrationRowError;
      color = GallaColors.danger;
    } else if (issues.contains(RowIssue.duplicate)) {
      text = l10n.migrationDuplicate;
      color = GallaColors.udhaar;
    } else if (issues.contains(RowIssue.uncertain) && include) {
      text = l10n.migrationUncertain;
      color = GallaColors.udhaar;
    }
    return Text(text,
        style: GallaText.caption.copyWith(color: color), maxLines: 1);
  }
}

class _DuplicateToggle extends StatelessWidget {
  const _DuplicateToggle({required this.include, required this.onChanged});
  final bool include;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => onChanged(!include),
        child: Text(
            include ? l10n.migrationSkipDuplicate : l10n.migrationImportAnyway),
      ),
    );
  }
}

// ----------------------------------------------------------------- party

class _PartyTile extends ConsumerStatefulWidget {
  const _PartyTile({super.key, required this.row, required this.assessment});
  final PartyImportRow row;
  final PartyAssessment assessment;

  @override
  ConsumerState<_PartyTile> createState() => _PartyTileState();
}

class _PartyTileState extends ConsumerState<_PartyTile> {
  late final _name = TextEditingController(text: widget.row.name);
  late final _phone = TextEditingController(text: widget.row.phone);
  late final _amount = TextEditingController(text: widget.row.amount);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final row = widget.row;
    final a = widget.assessment;
    final id = row.id;
    final negative = a.paisa < 0;
    final showPhone = row.phone.trim().isNotEmpty || _phone.text.isNotEmpty;

    return Opacity(
      opacity: row.include ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: _tileDecoration(a.issues, row.include),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _TileLabel(issues: a.issues, include: row.include)),
                Text(l10n.migrationAmount,
                    style: GallaText.caption.copyWith(color: GallaColors.muted)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.migrationRemoveRow,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => ctrl.removeParty(id),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: row.isBlank,
                    textCapitalization: TextCapitalization.words,
                    style: GallaText.bodyMedium.copyWith(fontSize: 17),
                    decoration: const InputDecoration.collapsed(hintText: ''),
                    onChanged: (v) => ctrl.updateParty(id, name: v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _amount,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    style: GallaText.display.copyWith(
                        fontSize: 18, color: GallaColors.udhaar),
                    decoration: const InputDecoration.collapsed(hintText: '0'),
                    onChanged: (v) => ctrl.updateParty(id, amount: v),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (showPhone)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: GallaText.body,
                  decoration: InputDecoration.collapsed(
                      hintText: l10n.migrationFieldPhone),
                  onChanged: (v) => ctrl.updateParty(id, phone: v),
                ),
              ),
            if (negative && !a.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.migrationNegativeHint,
                    style:
                        GallaText.caption.copyWith(color: GallaColors.udhaar)),
              ),
            if ((a.isDuplicate || !row.include) && !a.hasError)
              _DuplicateToggle(
                include: row.include,
                onChanged: (v) => ctrl.setPartyIncluded(id, v),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ item

class _ItemTile extends ConsumerStatefulWidget {
  const _ItemTile({super.key, required this.row, required this.assessment});
  final ItemImportRow row;
  final ItemAssessment assessment;

  @override
  ConsumerState<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends ConsumerState<_ItemTile> {
  late final _name = TextEditingController(text: widget.row.name);
  late final _unit = TextEditingController(text: widget.row.unit);
  late final _cost = TextEditingController(text: widget.row.cost);
  late final _price = TextEditingController(text: widget.row.price);
  late final _stock = TextEditingController(text: widget.row.stock);
  late final _low = TextEditingController(text: widget.row.low);
  late final _barcode = TextEditingController(text: widget.row.barcode);

  @override
  void dispose() {
    for (final c in [_name, _unit, _cost, _price, _stock, _low, _barcode]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _mini(String label, TextEditingController c, ValueChanged<String> on,
      {bool number = true}) {
    return SizedBox(
      width: 130,
      child: TextField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        style: GallaText.body,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
        ),
        onChanged: on,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final row = widget.row;
    final a = widget.assessment;
    final id = row.id;

    return Opacity(
      opacity: row.include ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
        decoration: _tileDecoration(a.issues, row.include),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _TileLabel(issues: a.issues, include: row.include)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.migrationRemoveRow,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => ctrl.removeItem(id),
                ),
              ],
            ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: GallaText.bodyMedium.copyWith(fontSize: 17),
              decoration: const InputDecoration.collapsed(hintText: ''),
              onChanged: (v) => ctrl.updateItem(id, name: v),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _mini(l10n.migrationFieldUnit, _unit,
                    (v) => ctrl.updateItem(id, unit: v),
                    number: false),
                _mini(l10n.migrationFieldCost, _cost,
                    (v) => ctrl.updateItem(id, cost: v)),
                _mini(l10n.migrationFieldPrice, _price,
                    (v) => ctrl.updateItem(id, price: v)),
                _mini(l10n.migrationFieldStock, _stock,
                    (v) => ctrl.updateItem(id, stock: v)),
                _mini(l10n.migrationFieldLow, _low,
                    (v) => ctrl.updateItem(id, low: v)),
                _mini(l10n.migrationFieldBarcode, _barcode,
                    (v) => ctrl.updateItem(id, barcode: v),
                    number: false),
              ],
            ),
            if ((a.isDuplicate || !row.include) && !a.hasError)
              _DuplicateToggle(
                include: row.include,
                onChanged: (v) => ctrl.setItemIncluded(id, v),
              ),
          ],
        ),
      ),
    );
  }
}
