import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';

/// Primary action: ink background, lime text, 60dp high (use [height] 64 for
/// the big "Bill banao" button). Set [lime] for the inverted lime variant.
class GallaPrimaryButton extends StatelessWidget {
  const GallaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.height = GallaSizes.primaryButtonHeight,
    this.lime = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Optional text on the right edge (e.g. "Rs 750").
  final String? trailing;
  final double height;
  final bool lime;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = lime ? GallaColors.lime : GallaColors.ink;
    final fg = lime ? GallaColors.ink : GallaColors.lime;
    final style = GallaText.buttonLabel.copyWith(color: fg);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: onPressed == null ? bg.withValues(alpha: 0.4) : bg,
        borderRadius: GallaRadius.card,
        child: InkWell(
          borderRadius: GallaRadius.card,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: trailing == null
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: 22),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (trailing != null) Text(trailing!, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: transparent with a 2dp ink outline.
class GallaOutlineButton extends StatelessWidget {
  const GallaOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 52,
    this.icon,
    this.dashed = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final IconData? icon;

  /// Not drawn dashed in Part 1; reserved for the photo / "Saman jodo" tiles.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: GallaRadius.card,
          side: const BorderSide(color: GallaColors.ink, width: 2),
        ),
        child: InkWell(
          borderRadius: GallaRadius.card,
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: GallaColors.ink, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: GallaText.buttonLabel.copyWith(
                    color: GallaColors.ink,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small ink pill used in headers, e.g. "+ Saman". 44dp touch target.
class GallaPillButton extends StatelessWidget {
  const GallaPillButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GallaColors.ink,
      borderRadius: BorderRadius.circular(GallaRadius.round),
      child: InkWell(
        borderRadius: BorderRadius.circular(GallaRadius.round),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: GallaSizes.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: GallaText.display.copyWith(
                  color: GallaColors.lime,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
