import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'empty_state.dart';
import 'galla_header.dart';

/// Body used by screens that are built in later parts. It already uses the
/// real theme and header, so every route looks right from Part 1.
class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({
    super.key,
    required this.title,
    this.showBack = true,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final bool showBack;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          GallaHeader(
            title: title,
            subtitle: subtitle,
            showBack: showBack,
            trailing: trailing,
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.construction_outlined,
              message: l10n.placeholderComingSoon,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen wrapper for routes outside the bottom-nav shell.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PlaceholderBody(title: title, subtitle: subtitle),
    );
  }
}
