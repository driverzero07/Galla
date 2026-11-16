import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';

/// Debug-only index of every design screen, so each route can be opened and
/// checked in the real theme before the business logic exists. Only
/// reachable from Menu in debug builds.
class DebugScreensScreen extends StatelessWidget {
  const DebugScreensScreen({super.key});

  static const _routes = <(String, String)>[
    ('Home', '/home'),
    ('Naya Bill', '/bill'),
    ('Aj ke bills', '/bills'),
    ('Khata (customers)', '/khata'),
    ('Purchase', '/purchase'),
    ('Purchase history', '/purchases'),
    ('Saman (inventory)', '/saman'),
    ('Saman add', '/saman/add'),
    ('Customer list', '/customers'),
    ('Supplier list', '/suppliers'),
    ('Aur (Menu)', '/menu'),
    ('Purani copy se data', '/migration'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const GallaHeader(title: 'Debug: screens', showBack: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: GallaSizes.screenPadding),
                children: [
                  for (final (name, path) in _routes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: GallaCard(
                        onTap: () => context.push(path),
                        child: Row(
                          children: [
                            Expanded(child: Text(name, style: GallaText.bodyMedium)),
                            Text(path, style: GallaText.caption),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
