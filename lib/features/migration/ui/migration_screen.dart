import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/migration_controller.dart';
import 'confirm_step.dart';
import 'done_step.dart';
import 'mapping_step.dart';
import 'method_step.dart';
import 'migration_texts.dart';
import 'quick_entry_step.dart';

/// Purani copy se data: pick how -> check -> done (with undo).
class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  @override
  void initState() {
    super.initState();
    // A fresh run every time the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(migrationControllerProvider.notifier).reset();
    });
  }

  void _goBack() {
    final ctrl = ref.read(migrationControllerProvider.notifier);
    if (!ctrl.back()) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(migrationControllerProvider);

    ref.listen<MigrationProblem?>(
      migrationControllerProvider.select((s) => s.problem),
      (_, p) {
        if (p == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(problemText(l10n, p))));
        ref.read(migrationControllerProvider.notifier).clearProblem();
      },
    );

    final atStart = state.phase == MigrationPhase.method ||
        state.phase == MigrationPhase.done;
    return PopScope(
      canPop: atStart,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              GallaHeader(
                title: l10n.migrationTitle,
                showBack: true,
                onBack: _goBack,
              ),
              _StepBar(step: state.step),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    GallaSizes.screenPadding, 8, GallaSizes.screenPadding, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.migrationStep(state.step, 3, stepTitle(l10n, state)),
                    style: GallaText.caption.copyWith(color: GallaColors.muted),
                  ),
                ),
              ),
              Expanded(
                child: switch (state.phase) {
                  MigrationPhase.method => const MethodStep(),
                  MigrationPhase.quick => const QuickEntryStep(),
                  MigrationPhase.mapping => const MappingStep(),
                  MigrationPhase.confirm => const ConfirmStep(),
                  MigrationPhase.done => const DoneStep(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three segments: done and current ones dark, the rest light.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GallaSizes.screenPadding),
      child: Row(
        children: [
          for (var i = 1; i <= 3; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: i <= step ? GallaColors.ink : GallaColors.chip,
                  borderRadius: BorderRadius.circular(GallaRadius.round),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
