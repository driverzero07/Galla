import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/migration/domain/column_mapping.dart';

void main() {
  group('headers', () {
    test('English headers are recognised', () {
      final t = [
        ['Name', 'Phone', 'Balance'],
        ['Akram', '03001234567', '3400'],
      ];
      expect(looksLikeHeader(t, ImportKind.customers), isTrue);
      final m = guessMapping(t, ImportKind.customers, hasHeader: true);
      expect(m[ImportField.name], 0);
      expect(m[ImportField.phone], 1);
      expect(m[ImportField.balance], 2);
    });

    test('Roman Urdu headers and different order', () {
      final t = [
        ['Baqaya', 'Naam'],
        ['3400', 'Akram'],
      ];
      final m = guessMapping(t, ImportKind.customers, hasHeader: true);
      expect(m[ImportField.name], 1);
      expect(m[ImportField.balance], 0);
      expect(m.containsKey(ImportField.phone), isFalse);
    });

    test('a data row is not a header', () {
      final t = [
        ['Akram Sahib', '3400'],
        ['Bilal Bhai', '12750'],
      ];
      expect(looksLikeHeader(t, ImportKind.customers), isFalse);
    });

    test('a column is never used for two fields', () {
      final t = [
        ['Name', 'Amount'],
        ['A', '1'],
      ];
      final m = guessMapping(t, ImportKind.customers, hasHeader: true);
      expect(m.values.toSet().length, m.length);
    });
  });

  group('no header', () {
    test('two columns are name + balance', () {
      final t = [
        ['Akram', '3400'],
      ];
      final m = guessMapping(t, ImportKind.customers, hasHeader: false);
      expect(m[ImportField.name], 0);
      expect(m[ImportField.balance], 1);
    });

    test('three columns are name, phone, balance', () {
      final t = [
        ['Akram', '0300', '3400'],
      ];
      final m = guessMapping(t, ImportKind.customers, hasHeader: false);
      expect(m[ImportField.phone], 1);
      expect(m[ImportField.balance], 2);
    });
  });

  group('rows', () {
    test('party rows skip the header and blank lines', () {
      final t = [
        ['Name', 'Balance'],
        ['Akram', '3,400'],
        ['', ''],
        ['Bilal', '12,750'],
      ];
      final m = guessMapping(t, ImportKind.customers, hasHeader: true);
      final rows = partyRowsFromTable(t, m, hasHeader: true);
      expect(rows.map((r) => r.name), ['Akram', 'Bilal']);
      expect(rows.map((r) => r.amount), ['3,400', '12,750']);
      expect(rows.map((r) => r.id), [0, 1]);
    });

    test('short rows do not crash', () {
      final t = [
        ['Akram'],
      ];
      final rows = partyRowsFromTable(
          t, {ImportField.name: 0, ImportField.balance: 2},
          hasHeader: false);
      expect(rows.single.amount, '');
    });

    test('item rows', () {
      final t = [
        ['Name', 'Unit', 'Cost', 'Price', 'Stock', 'Barcode'],
        ['Cheeni', 'kg', '150', '170', '25', '8961'],
      ];
      final m = guessMapping(t, ImportKind.items, hasHeader: true);
      final rows = itemRowsFromTable(t, m, hasHeader: true);
      expect(rows.single.name, 'Cheeni');
      expect(rows.single.unit, 'kg');
      expect(rows.single.cost, '150');
      expect(rows.single.price, '170');
      expect(rows.single.stock, '25');
      expect(rows.single.barcode, '8961');
    });
  });
}
