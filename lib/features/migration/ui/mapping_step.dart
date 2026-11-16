import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/column_mapping.dart';
import '../domain/migration_controller.dart';
import 'migration_texts.dart';

/// Which column of the file is the name, phone, amount...
class MappingStep extends ConsumerWidget {
  const MappingStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(migrationControllerProvider);
    final ctrl = ref.read(migrationControllerProvider.notifier);
    final width = s.table.isEmpty ? 0 : s.table.first.length;

    String columnLabel(int c) {
      if (s.hasHeader) {
        final h = s.table.first[c].trim();
        if (h.isNotEmpty) return h;
      }
      return l10n.migrationColumn(c + 1);
    }

    final firstData = s.hasHeader ? 1 : 0;
    final preview = s.table.skip(firstData).take(3).toList();
    final hasName = s.mapping.containsKey(ImportField.name);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: GallaSizes.screenPadding, vertical: 4),
            children: [
              Text(l10n.migrationFileName(s.fileName),
                  style: GallaText.bodyMedium),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.migrationHasHeader, style: GallaText.body),
                value: s.hasHeader,
                onChanged: ctrl.setHasHeader,
              ),
              Text(l10n.migrationMapHint,
                  style: GallaText.caption.copyWith(color: GallaColors.muted)),
              const SizedBox(height: 8),
              for (final f in fieldsFor(s.kind))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('${f.name}-${s.mapping[f]}-${s.hasHeader}'),
                    value: s.mapping[f],
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: fieldLabel(l10n, f)),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(l10n.migrationNotInFile),
                      ),
                      for (var c = 0; c < width; c++)
                        DropdownMenuItem<int?>(
                          value: c,
                          child: Text(columnLabel(c),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => ctrl.setMapping(f, v),
                  ),
                ),
              if (!hasName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l10n.migrationNameColumnNeeded,
                      style:
                          GallaText.caption.copyWith(color: GallaColors.danger)),
                ),
              Text(l10n.migrationPreview, style: GallaText.bodyMedium),
              const SizedBox(height: 6),
              GallaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in preview)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          r.where((c) => c.trim().isNotEmpty).join(',  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GallaText.body,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(GallaSizes.screenPadding),
          child: GallaPrimaryButton(
            label: l10n.migrationNext,
            onPressed: hasName ? ctrl.applyMapping : null,
          ),
        ),
      ],
    );
  }
}
