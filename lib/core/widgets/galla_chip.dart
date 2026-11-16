import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';

enum GallaChipTone { normal, selected, danger, warning }

/// Fully rounded chip. `normal` = #DDF99B, `selected` = ink/lime,
/// `danger` = red tint (e.g. "Khatam hone wala"), `warning` = amber tint.
class GallaChip extends StatelessWidget {
  const GallaChip({
    super.key,
    required this.label,
    this.tone = GallaChipTone.normal,
    this.onTap,
    this.icon,
  });

  final String label;
  final GallaChipTone tone;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (tone) {
      GallaChipTone.normal => (GallaColors.chip, GallaColors.ink, null),
      GallaChipTone.selected => (GallaColors.ink, GallaColors.lime, null),
      GallaChipTone.danger => (
          GallaColors.dangerBg,
          GallaColors.danger,
          GallaColors.dangerBorder,
        ),
      GallaChipTone.warning => (
          GallaColors.warningBg,
          GallaColors.udhaar,
          GallaColors.warningBorder,
        ),
    };
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(GallaRadius.round),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: GallaFonts.body,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: fg,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    // Keep the visual chip compact but the touch target >= 44dp.
    return InkWell(
      borderRadius: BorderRadius.circular(GallaRadius.round),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: GallaSizes.touch),
        child: Center(widthFactor: 1, child: chip),
      ),
    );
  }
}
