import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/env.dart';
import '../core/theme/colors.dart';
import '../core/widgets/galla_logo.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/auth/domain/auth_controller.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/ui/setup_screen.dart';
import '../features/bill/ui/bill_detail_screen.dart';
import '../features/bill/ui/bill_done_screen.dart';
import '../features/bill/ui/bill_screen.dart';
import '../features/bill/ui/bills_screen.dart';
import '../features/bill/ui/return_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../features/customers/ui/customers_screen.dart';
import '../features/home/ui/alerts_screen.dart';
import '../features/inventory/ui/saman_add_screen.dart';
import '../features/inventory/ui/saman_screen.dart';
import '../features/khata/ui/khata_detail_screen.dart';
import '../features/khata/ui/khata_screen.dart';
import '../features/menu/ui/debug_screens_screen.dart';
import '../features/menu/ui/menu_screen.dart';
import '../features/migration/ui/migration_screen.dart';
import '../features/purchase/ui/purchase_screen.dart';
import '../features/purchase/ui/purchase_detail_screen.dart';
import '../features/purchase/ui/purchases_screen.dart';
import '../features/suppliers/ui/supplier_screen.dart';
import '../features/suppliers/ui/suppliers_screen.dart';
import 'app_shell.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const setup = '/setup';
  static const login = '/login';
  static const home = '/home';
  static const bill = '/bill';
  static const billDone = '/bill/done/:saleId';
  static const bills = '/bills';
  static const billDetail = '/bills/:saleId';
  static const billReturn = '/bills/:saleId/return';
  static const khata = '/khata';
  static const khataDetail = '/khata/:customerId';
  static const purchase = '/purchase';
  static const supplier = '/supplier/:supplierId';
  static const purchases = '/purchases';
  static const purchaseDetail = '/purchases/:purchaseId';
  static const customers = '/customers';
  static const suppliers = '/suppliers';
  static const saman = '/saman';
  static const alerts = '/alerts';
  static const samanAdd = '/saman/add';
  static const menu = '/menu';
  static const migration = '/migration';
  static const settings = '/settings';
  static const debugScreens = '/debug';
}

/// Tells go_router to re-run its redirect whenever auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) => notifyListeners());
  }
}

String? redirectForAuth(AuthState auth, String location) {
  const gate = {Routes.splash, Routes.login, Routes.setup};
  return switch (auth) {
    AuthLoading() => location == Routes.splash ? null : Routes.splash,
    AuthNeedsSetup() => location == Routes.setup ? null : Routes.setup,
    AuthLocked() => location == Routes.login ? null : Routes.login,
    AuthUnlocked() => gate.contains(location) ? Routes.home : null,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        redirectForAuth(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const _SplashScreen()),
      GoRoute(path: Routes.setup, builder: (_, __) => const SetupScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),

      // Screens with the bottom nav.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
          GoRoute(path: Routes.khata, builder: (_, __) => const KhataScreen()),
          GoRoute(
              path: Routes.purchase,
              builder: (_, state) => PurchaseScreen(
                  initialSupplierId: state.uri.queryParameters['supplier'])),
        ],
      ),

      // Full-screen routes (back button instead of the nav).
      GoRoute(path: Routes.bill, builder: (_, __) => const BillScreen()),
      GoRoute(
          path: Routes.billDone,
          builder: (_, state) =>
              BillDoneScreen(saleId: state.pathParameters['saleId']!)),
      GoRoute(path: Routes.bills, builder: (_, __) => const BillsScreen()),
      GoRoute(
          path: Routes.billDetail,
          builder: (_, state) =>
              BillDetailScreen(saleId: state.pathParameters['saleId']!)),
      GoRoute(
          path: Routes.billReturn,
          builder: (_, state) =>
              ReturnScreen(saleId: state.pathParameters['saleId']!)),
      GoRoute(
          path: Routes.khataDetail,
          builder: (_, state) =>
              KhataDetailScreen(customerId: state.pathParameters['customerId']!)),
      GoRoute(
          path: Routes.supplier,
          builder: (_, state) =>
              SupplierScreen(supplierId: state.pathParameters['supplierId']!)),
      GoRoute(
          path: Routes.purchases, builder: (_, __) => const PurchasesScreen()),
      GoRoute(
          path: Routes.purchaseDetail,
          builder: (_, state) => PurchaseDetailScreen(
              purchaseId: state.pathParameters['purchaseId']!)),
      GoRoute(
        path: Routes.saman,
        builder: (_, state) => SamanScreen(
            initialLowOnly: state.uri.queryParameters['low'] == '1'),
      ),
      GoRoute(path: Routes.alerts, builder: (_, __) => const AlertsScreen()),
      GoRoute(
        path: Routes.samanAdd,
        builder: (_, state) {
          final id = state.uri.queryParameters['id'];
          // Key by id so replacing one edit page with another rebuilds it.
          return SamanAddScreen(key: ValueKey(id ?? 'new'), itemId: id);
        },
      ),
      GoRoute(
          path: Routes.customers, builder: (_, __) => const CustomersScreen()),
      GoRoute(
          path: Routes.suppliers, builder: (_, __) => const SuppliersScreen()),
      GoRoute(path: Routes.menu, builder: (_, __) => const MenuScreen()),
      GoRoute(
          path: Routes.migration, builder: (_, __) => const MigrationScreen()),
      GoRoute(
          path: Routes.settings, builder: (_, __) => const SettingsScreen()),
      if (kDebugMode && Env.enableDebugTools)
        GoRoute(
            path: Routes.debugScreens,
            builder: (_, __) => const DebugScreensScreen()),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: GallaColors.background,
      body: Center(child: GallaLogo(size: 96)),
    );
  }
}
