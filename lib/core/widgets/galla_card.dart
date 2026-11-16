import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';

/// Standard card: #F8FFF0, radius 8, soft shadow. Set [hero] for the dark
/// gradient variant used for the big balance / sales numbers.
class GallaCard extends StatelessWidget {
  const GallaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.hero = false,
    this.color,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool hero;
  final Color? color;
  final BoxBorder? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: hero ? null : (color ?? GallaColors.card),
      gradient: hero
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [GallaColors.heroStart, GallaColors.heroEnd],
            )
          : null,
      borderRadius: GallaRadius.card,
      boxShadow: GallaShadows.card,
      border: border,
    );
    final content = Padding(padding: padding, child: child);
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: GallaRadius.card,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
