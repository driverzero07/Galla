import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/import_repository.dart';
import '../domain/migration_controller.dart';
import 'migration_texts.dart';

/// Step 1: what to bring in, and how. Also lists earlier imports with Undo.
class MethodStep extends ConsumerWidget {
  const MethodStep({super.key});

  Future<void> _pickFile(WidgetRef ref) async {
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt', 'tsv', 'xlsx', 'ods'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    ctrl.loadFile(f.bytes ?? Uint8List(0), f.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(migrationControllerProvider);
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final batches = ref.watch(importBatchesProvider).valueOrNull ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 24),
      children: [
        Text(l10n.migrationKindQuestion, style: GallaText.bodyMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final k in const [
              ImportKind.customers,
              ImportKind.suppliers,
              ImportKind.items,
            ]) ...[
              Expanded(
                child: _KindButton(
                  label: kindLabel(l10n, k),
                  selected: state.kind == k,
                  onTap: () => ctrl.setKind(k),
                ),
              ),
              if (k != ImportKind.items) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (!state.isItems)
          _MethodCard(
            icon: Icons.edit_outlined,
            title: l10n.migrationMethodQuick,
            hint: l10n.migrationMethodQuickHint,
            onTap: ctrl.startQuick,
          ),
        _MethodCard(
          icon: Icons.table_chart_outlined,
          title: l10n.migrationMethodFile,
          hint: l10n.migrationMethodFileHint,
          onTap: () => _pickFile(ref),
        ),
        if (FeatureFlags.ocrImport && !state.isItems)
          _MethodCard(
            icon: Icons.photo_camera_outlined,
            title: l10n.migrationMethodPhoto,
            hint: l10n.migrationMethodPhotoHint,
            busy: state.busy,
            onTap: ctrl.startOcr,
          ),
        if (batches.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(l10n.migrationHistoryTitle, style: GallaText.bodyMedium),
          const SizedBox(height: 8),
          for (final b in batches) _HistoryTile(batch: b),
        ],
      ],
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(GallaRadius.base),
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GallaColors.ink : GallaColors.card,
            borderRadius: BorderRadius.circular(GallaRadius.base),
            border: Border.all(color: GallaColors.ink, width: 1.5),
          ),
          child: Text(
            label,
            style: GallaText.bodyMedium.copyWith(
              color: selected ? GallaColors.lime : GallaColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GallaCard(
        onTap: busy ? null : onTap,
        child: Row(
          children: [
            Icon(icon, size: 28, color: GallaColors.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GallaText.heading.copyWith(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(hint,
                      style:
                          GallaText.caption.copyWith(color: GallaColors.muted)),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.chevron_right, color: GallaColors.ink),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.batch});
  final ImportBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final undone = batch.undoneAt != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GallaCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.migrationHistoryLine(
                  kindLabel(l10n, batch.kind),
                  batch.rowCount,
                  DateFormat('d MMM yyyy').format(batch.createdAt),
                ),
                style: GallaText.body.copyWith(
                  color: undone ? GallaColors.muted : GallaColors.ink,
                ),
              ),
            ),
            if (undone)
              Text(l10n.migrationUndone,
                  style: GallaText.caption.copyWith(color: GallaColors.muted))
            else
              TextButton(
                onPressed: () => confirmUndoBatch(context, ref, batch.id),
                child: Text(l10n.migrationUndo),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks, checks nothing was touched since, then undoes a whole batch.
Future<void> confirmUndoBatch(
    BuildContext context, WidgetRef ref, String batchId) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(importRepositoryProvider);

  final blocked = await repo.blockedCount(batchId);
  if (blocked > 0) {
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.migrationUndoBlocked(blocked))));
    return;
  }
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.migrationUndoTitle),
      content: Text(l10n.migrationUndoBody),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.migrationUndo)),
      ],
    ),
  );
  if (yes != true) return;
  try {
    await repo.undoBatch(batchId);
    messenger.showSnackBar(SnackBar(content: Text(l10n.migrationUndoDone)));
  } on ImportException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.error == ImportError.undoBlocked
          ? l10n.migrationUndoBlocked(e.count)
          : l10n.migrationErrSave),
    ));
  }
}
