import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/db/db_providers.dart';
import 'package:galla/core/theme/galla_theme.dart';
import 'package:galla/features/auth/data/shop_repository.dart';
import 'package:galla/features/auth/domain/current_shop.dart';
import 'package:galla/features/bill/ui/bill_screen.dart';
import 'package:galla/features/inventory/data/inventory_repository.dart';
import 'package:galla/l10n/gen/app_localizations.dart';

/// The common case end to end on screen: open Bill, find an item, tap it,
/// "Bill banao" -> the sale is saved and the done screen opens.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('search item, tap, Bill banao saves one sale', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final l10n = lookupAppLocalizations(const Locale('en'));
    final now = DateTime.now();

    await tester.runAsync(() async {
      await ShopRepository(db).createShop(
          shopId: 'shop1', shopName: 'S', phone: '+923001234567', now: now);
      await InventoryRepository(db, () => 'shop1', () => now).createItem(
          const ItemInput(
              name: 'Cheeni',
              unit: ItemUnit.kg,
              costPrice: 16500,
              salePrice: 18000),
          openingStock: 50000);
    });

    final router = GoRouter(
      initialLocation: '/bill',
      routes: [
        GoRoute(path: '/bill', builder: (_, __) => const BillScreen()),
        GoRoute(
            path: '/bill/done/:saleId',
            builder: (_, __) => const Scaffold(body: Text('BILL DONE'))),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWithValue('shop1'),
      ],
      child: MaterialApp.router(
        theme: buildGallaTheme(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));

    Future<void> settle() async {
      // Drift streams answer on real time, not on the fake test clock.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await settle();
    expect(find.text(l10n.billEmptyCart), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Chee');
    await settle();
    await tester.tap(find.text('Cheeni').first);
    await settle();
    expect(find.text(l10n.billEmptyCart), findsNothing);

    await tester.tap(find.text(l10n.billMake));
    await settle();
    await settle();

    expect(find.text('BILL DONE'), findsOneWidget);
    final sales = await tester.runAsync(() => db.select(db.sales).get());
    expect(sales, hasLength(1));
    expect(sales!.single.total, 18000);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
