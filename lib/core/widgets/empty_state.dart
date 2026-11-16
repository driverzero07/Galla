import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';
import 'galla_buttons.dart';

/// First-day / nothing-here state: one icon, one sentence, one next step.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: GallaColors.muted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GallaText.bodyMedium.copyWith(color: GallaColors.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              GallaPrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
