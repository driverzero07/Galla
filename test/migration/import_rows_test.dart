import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/migration/domain/import_rows.dart';
import 'package:galla/features/migration/domain/ocr_response.dart';

void main() {
  PartyAssessment a(PartyImportRow r,
          {Set<String> existing = const {}, Set<String> seen = const {}}) =>
      assessParty(r, existingKeys: existing, seenInBatch: seen);

  group('assessParty', () {
    test('clean row has no issues', () {
      final r = a(const PartyImportRow(id: 0, name: 'Akram', amount: '3,400'));
      expect(r.issues, isEmpty);
      expect(r.paisa, 340000);
    });

    test('empty name and unreadable amount are errors', () {
      expect(a(const PartyImportRow(id: 0, name: '', amount: '5')).hasError,
          isTrue);
      expect(a(const PartyImportRow(id: 0, name: 'A b', amount: 'xyz')).hasError,
          isTrue);
    });

    test('question mark, negative, bad phone are uncertain', () {
      expect(
          a(const PartyImportRow(id: 0, name: 'Fatima', amount: '860 ?'))
              .isUncertain,
          isTrue);
      expect(
          a(const PartyImportRow(id: 0, name: 'Fatima', amount: '-5')).isUncertain,
          isTrue);
      expect(
          a(const PartyImportRow(
                  id: 0, name: 'Fatima', amount: '5', phone: '12'))
              .isUncertain,
          isTrue);
    });

    test('source uncertainty is shown until edited', () {
      expect(
          a(const PartyImportRow(
                  id: 0, name: 'Fatima', amount: '5', sourceUncertain: true))
              .isUncertain,
          isTrue);
    });

    test('duplicate of existing and of earlier row in batch', () {
      final existing = {partyKey('Akram', '')};
      expect(
          a(const PartyImportRow(id: 0, name: ' akram ', amount: '1'),
                  existing: existing)
              .isDuplicate,
          isTrue);
      final all = assessAllParties([
        const PartyImportRow(id: 0, name: 'Bilal', amount: '1'),
        const PartyImportRow(id: 1, name: 'BILAL', amount: '2'),
      ], existingKeys: {});
      expect(all[0].isDuplicate, isFalse);
      expect(all[1].isDuplicate, isTrue);
    });

    test('same name with different phones is not a duplicate', () {
      final existing = {partyKey('Akram', '03001234567')};
      expect(
          a(const PartyImportRow(
                      id: 0, name: 'Akram', amount: '1', phone: '03111234567'),
                  existing: existing)
              .isDuplicate,
          isFalse);
    });
  });

  group('items', () {
    ItemAssessment i(ItemImportRow r,
            {Set<String> names = const {}, Set<String> codes = const {}}) =>
        assessItem(r,
            existingNames: names,
            existingBarcodes: codes,
            seenNames: {},
            seenBarcodes: {});

    test('units are mapped', () {
      expect(mapUnit('Kilo'), ItemUnit.kg);
      expect(mapUnit('pcs'), ItemUnit.piece);
      expect(mapUnit('Packet'), ItemUnit.pack);
      expect(mapUnit('dozen'), ItemUnit.dozen);
      expect(mapUnit('furlong'), isNull);
    });

    test('clean item', () {
      final r = i(const ItemImportRow(
          id: 0, name: 'Cheeni', unit: 'kg', cost: '150', price: '170', stock: '25'));
      expect(r.issues, isEmpty);
      expect(r.cost, 15000);
      expect(r.price, 17000);
      expect(r.stock, 25000);
      expect(r.unit, ItemUnit.kg);
    });

    test('unknown unit is uncertain, bad price is an error', () {
      expect(i(const ItemImportRow(id: 0, name: 'X', unit: 'zz')).isUncertain,
          isTrue);
      expect(i(const ItemImportRow(id: 0, name: 'X', price: 'abc')).hasError,
          isTrue);
      expect(i(const ItemImportRow(id: 0, name: 'X', price: '-5')).hasError,
          isTrue);
    });

    test('duplicate name is flagged, repeated barcode is an error', () {
      expect(
          i(const ItemImportRow(id: 0, name: 'Cheeni'), names: {'cheeni'})
              .isDuplicate,
          isTrue);
      final b = i(const ItemImportRow(id: 0, name: 'Y', barcode: '123'),
          codes: {'123'});
      expect(b.hasError, isTrue);
      expect(b.isDuplicate, isTrue);
    });
  });

  group('ocr response', () {
    test('parses entries and flags low confidence', () {
      final entries = parseOcrResponse({
        'entries': [
          {'name': 'Akram', 'amount': '3400', 'confidence': 0.95},
          {'name': 'Fatima', 'amount': '860 ?', 'confidence': 0.5},
          {'name': '', 'amount': '1'},
          'junk',
        ]
      });
      expect(entries, hasLength(2));
      final rows = rowsFromOcr(entries);
      expect(rows[0].sourceUncertain, isFalse);
      expect(rows[1].sourceUncertain, isTrue);
    });

    test('accepts a JSON string and survives garbage', () {
      expect(parseOcrResponse('{"entries":[{"name":"A","amount":1,"confidence":1}]}'),
          hasLength(1));
      expect(parseOcrResponse('not json'), isEmpty);
      expect(parseOcrResponse(null), isEmpty);
      expect(parseOcrResponse({'entries': 5}), isEmpty);
    });
  });
}
