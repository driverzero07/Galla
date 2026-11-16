import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';
import 'galla_logo.dart';

/// Round card-coloured back button used on detail screens.
class GallaBackButton extends StatelessWidget {
  const GallaBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: GallaColors.card,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed ??
              () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
          child: const Icon(Icons.chevron_left,
              size: 28, color: GallaColors.ink),
        ),
      ),
    );
  }
}

/// Screen header: leading is either the G logo (tap -> Home) or a back
/// button; then a title (and optional subtitle) and optional trailing widget.
class GallaHeader extends StatelessWidget {
  const GallaHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.trailing,
    this.onBack,
  });

  /// Replaces the default back action (pop) when a screen has steps.
  final VoidCallback? onBack;
  final String title;
  final String? subtitle;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GallaSizes.screenPadding,
        12,
        GallaSizes.screenPadding,
        8,
      ),
      child: Row(
        children: [
          if (showBack)
            GallaBackButton(onPressed: onBack)
          else
            GallaLogo(onTap: () => context.go('/home')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: GallaText.heading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!,
                      style: GallaText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
