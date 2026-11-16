import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/import_repository.dart';
import '../domain/migration_controller.dart';

/// Step 3: how many were saved, and a one-tap Undo.
class DoneStep extends ConsumerWidget {
  const DoneStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(migrationControllerProvider);
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final res = s.result;

    Future<void> undo() async {
      final messenger = ScaffoldMessenger.of(context);
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
      final err = await ctrl.undoCurrent();
      if (err == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.migrationUndoDone)));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(err.error == ImportError.undoBlocked
              ? l10n.migrationUndoBlocked(err.count)
              : l10n.migrationErrSave),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.all(GallaSizes.screenPadding),
      child: Column(
        children: [
          GallaCard(
            child: Row(
              children: [
                Icon(
                  s.undone ? Icons.undo : Icons.check_circle,
                  size: 36,
                  color: s.undone ? GallaColors.muted : GallaColors.received,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.undone
                            ? l10n.migrationUndoDone
                            : l10n.migrationDoneCount(res?.count ?? 0),
                        style: GallaText.heading.copyWith(fontSize: 20),
                      ),
                      if (!s.undone && !s.isItems && res != null)
                        Text(
                          l10n.migrationDoneTotal(formatPaisa(res.totalAmount)),
                          style: GallaText.body
                              .copyWith(color: GallaColors.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!s.undone) ...[
            GallaOutlineButton(label: l10n.migrationUndo, onPressed: undo),
            const SizedBox(height: 10),
          ],
          GallaPrimaryButton(
            label: l10n.migrationDoneButton,
            onPressed: () {
              ctrl.reset();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
        ],
      ),
    );
  }
}
