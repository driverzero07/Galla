import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/utils/money.dart';

void main() {
  group('formatPaisa (en_IN grouping)', () {
    test('uses Indian grouping', () {
      expect(formatPaisa(18430000), 'Rs 1,84,300');
      expect(formatPaisa(1845000), 'Rs 18,450');
      expect(formatPaisa(100000000), 'Rs 10,00,000');
      expect(formatPaisa(8500000), 'Rs 85,000');
    });

    test('hides paisa when zero, shows two digits otherwise', () {
      expect(formatPaisa(0), 'Rs 0');
      expect(formatPaisa(1234), 'Rs 12.34');
      expect(formatPaisa(5), 'Rs 0.05');
      expect(formatPaisa(150), 'Rs 1.50');
    });

    test('negative values and no-symbol mode', () {
      expect(formatPaisa(-50000), '-Rs 500');
      expect(formatPaisa(-1234), '-Rs 12.34');
      expect(formatPaisa(120000, symbol: false), '1,200');
    });
  });

  group('formatQty', () {
    test('thousandths', () {
      expect(formatQty(2500), '2.5');
      expect(formatQty(2000), '2');
      expect(formatQty(125), '0.125');
      expect(formatQty(1500000), '1,500');
      expect(formatQty(-2500), '-2.5');
    });
  });

  group('parsing', () {
    test('rupees to paisa', () {
      expect(parseRupeesToPaisa('1,200'), 120000);
      expect(parseRupeesToPaisa(' Rs 300 '), 30000);
      expect(parseRupeesToPaisa('12.5'), 1250);
      expect(parseRupeesToPaisa('0.5'), 50);
      expect(parseRupeesToPaisa('12.567'), 1256); // extra digits dropped
    });

    test('quantity to thousandths', () {
      expect(parseQtyToMilli('2.5'), 2500);
      expect(parseQtyToMilli('3'), 3000);
      expect(parseQtyToMilli('0.125'), 125);
    });

    test('rejects junk and negatives', () {
      expect(parseRupeesToPaisa(''), isNull);
      expect(parseRupeesToPaisa('abc'), isNull);
      expect(parseRupeesToPaisa('-5'), isNull);
      expect(parseQtyToMilli('1.2.3'), isNull);
    });
  });

  group('editable text', () {
    test('plain rupees have no grouping or trailing zeros', () {
      expect(formatPaisaPlain(16500), '165');
      expect(formatPaisaPlain(1250), '12.5');
      expect(formatPaisaPlain(1205), '12.05');
      expect(formatPaisaPlain(18430000), '184300');
      expect(parseRupeesToPaisa(formatPaisaPlain(1205)), 1205);
    });

    test('plain quantities round trip', () {
      expect(formatQtyPlain(2500), '2.5');
      expect(formatQtyPlain(50000), '50');
      expect(formatQtyPlain(125), '0.125');
      expect(parseQtyToMilli(formatQtyPlain(125)), 125);
    });
  });
}
