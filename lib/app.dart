import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/sync/sync_service.dart';
import 'core/theme/galla_theme.dart';
import 'features/auth/domain/auth_controller.dart';
import 'l10n/gen/app_localizations.dart';
import 'router/app_router.dart';

class GallaApp extends ConsumerStatefulWidget {
  const GallaApp({super.key});

  @override
  ConsumerState<GallaApp> createState() => _GallaAppState();
}

class _GallaAppState extends ConsumerState<GallaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = ref.read(authControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        auth.onBackgrounded();
      case AppLifecycleState.resumed:
        auth.onForegrounded();
        ref.read(syncServiceProvider).syncNow(reason: 'resume');
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncWorkerProvider); // reconnect + 5 minute sync triggers
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Galla',
      debugShowCheckedModeBanner: false,
      theme: buildGallaTheme(),
      routerConfig: router,
      // v1 text is Roman Urdu, which lives in the `en` (Latin) ARB. Urdu
      // script is added later as app_ur.arb.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
