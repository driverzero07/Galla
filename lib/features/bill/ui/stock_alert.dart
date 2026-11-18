import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inventory/ui/saman_screen.dart' show unitLabel;

/// "Itna stock nahi hai": shown when an item is not in the inventory at all
/// or more is asked for than is on hand. The sale never goes through.
Future<void> showStockAlert(BuildContext context, WidgetRef ref, String name,
    String unit, int available) {
  final l10n = AppLocalizations.of(context);
  final unitText = unit.isEmpty ? '' : ' ${unitLabel(l10n, unit)}';
  final body = available <= 0
      ? l10n.stockNoneBody(name)
      : l10n.stockOnlyBody(name, '${formatQty(available)}$unitText');
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded,
          color: GallaColors.danger, size: 36),
      title: Text(l10n.stockNotEnoughTitle, style: GallaText.heading),
      content: Text(body, style: GallaText.body),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l10n.ok)),
      ],
    ),
  );
}
