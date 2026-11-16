import 'package:flutter_test/flutter_test.dart';
import 'package:galla/features/migration/domain/import_numbers.dart';

String arabicDigits(String ascii) => String.fromCharCodes(
    ascii.codeUnits.map((c) => c >= 0x30 && c <= 0x39 ? c - 0x30 + 0x0660 : c));
String urduDigits(String ascii) => String.fromCharCodes(
    ascii.codeUnits.map((c) => c >= 0x30 && c <= 0x39 ? c - 0x30 + 0x06F0 : c));

void main() {
  group('normalizeDigits', () {
    test('Arabic-Indic and Urdu digits become 0-9', () {
      expect(normalizeDigits(arabicDigits('3400')), '3400');
      expect(normalizeDigits(urduDigits('0300 12')), '0300 12');
    });
    test('invisible characters become spaces', () {
      expect(normalizeDigits('a${String.fromCharCode(0xFEFF)}b'), 'a b');
    });
  });

  group('parseImportAmount', () {
    int paisa(String s) => parseImportAmount(s).paisa;

    test('plain, Western and Indian commas', () {
      expect(paisa('3400'), 340000);
      expect(paisa('3,400'), 340000);
      expect(paisa('12,750'), 1275000);
      expect(paisa('1,25,000'), 12500000);
      expect(parseImportAmount('1,25,000').uncertain, isFalse);
      expect(parseImportAmount('3,400').uncertain, isFalse);
    });

    test('Urdu digits', () {
      expect(paisa(arabicDigits('3400')), 340000);
      expect(paisa(urduDigits('860')), 86000);
    });

    test('currency words and symbols are ignored', () {
      expect(paisa('Rs 3400'), 340000);
      expect(paisa('Rs. 3,400/-'), 340000);
      expect(paisa('PKR 500'), 50000);
    });

    test('question mark means uncertain, not wrong', () {
      final a = parseImportAmount('860 ?');
      expect(a.paisa, 86000);
      expect(a.uncertain, isTrue);
      expect(a.error, isFalse);
    });

    test('negative: minus and brackets', () {
      expect(paisa('-500'), -50000);
      expect(paisa('(500)'), -50000);
    });

    test('decimals round half up at the paisa', () {
      expect(paisa('12.5'), 1250);
      final a = parseImportAmount('12.345');
      expect(a.paisa, 1235);
      expect(a.uncertain, isTrue);
    });

    test('odd comma placement is uncertain', () {
      final a = parseImportAmount('12,34');
      expect(a.paisa, 123400);
      expect(a.uncertain, isTrue);
    });

    test('blank is zero, text is an error, huge is an error', () {
      expect(parseImportAmount('').paisa, 0);
      expect(parseImportAmount('').error, isFalse);
      expect(parseImportAmount('abc').error, isTrue);
      expect(parseImportAmount('1234567890').error, isTrue);
    });
  });

  group('parseImportQty', () {
    test('thousandths', () {
      expect(parseImportQty('2.5'), 2500);
      expect(parseImportQty('1,000'), 1000000);
      expect(parseImportQty('-3'), -3000);
      expect(parseImportQty(''), 0);
      expect(parseImportQty('x'), isNull);
    });
  });
}
