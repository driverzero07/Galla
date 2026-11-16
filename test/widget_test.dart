import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/theme/galla_theme.dart';
import 'package:galla/core/widgets/galla_buttons.dart';
import 'package:galla/core/widgets/galla_chip.dart';
import 'package:galla/core/widgets/galla_nav_bar.dart';
import 'package:galla/core/widgets/money_text.dart';
import 'package:galla/features/auth/ui/pin_field.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildGallaTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('MoneyText formats paisa with en_IN grouping', (tester) async {
    await tester.pumpWidget(_wrap(const MoneyText(18430000)));
    expect(find.text('Rs 1,84,300'), findsOneWidget);
  });

  testWidgets('MoneyText signed shows + and -', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      MoneyText(120000, signed: true),
      MoneyText(-200000, signed: true),
    ])));
    expect(find.text('+ Rs 1,200'), findsOneWidget);
    expect(find.text('- Rs 2,000'), findsOneWidget);
  });

  testWidgets('primary button is at least 60dp high and tappable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(
        GallaPrimaryButton(label: 'Dukan kholo', onPressed: () => taps++)));
    expect(tester.getSize(find.byType(GallaPrimaryButton)).height,
        greaterThanOrEqualTo(60));
    await tester.tap(find.text('Dukan kholo'));
    expect(taps, 1);
  });

  testWidgets('nav bar reports Khata / Bill / Purchase taps', (tester) async {
    final tapped = <GallaNavItem>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildGallaTheme(),
      home: Scaffold(
        bottomNavigationBar: GallaNavBar(
          selected: GallaNavItem.khata,
          onSelected: tapped.add,
          khataLabel: 'Khata',
          billLabel: 'Bill',
          purchaseLabel: 'Purchase',
        ),
      ),
    ));
    await tester.tap(find.text('Khata'));
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.tap(find.text('Purchase'));
    expect(tapped,
        [GallaNavItem.khata, GallaNavItem.bill, GallaNavItem.purchase]);
  });

  testWidgets('chip with onTap keeps a 44dp touch target', (tester) async {
    await tester.pumpWidget(_wrap(GallaChip(label: 'Sab', onTap: () {})));
    expect(tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(44));
  });

  testWidgets('PinField calls onCompleted once at 4 digits', (tester) async {
    final controller = TextEditingController();
    final completed = <String>[];
    await tester.pumpWidget(_wrap(
        PinField(controller: controller, onCompleted: completed.add)));
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump();
    expect(completed, ['1234']);
  });
}
