import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galla/features/migration/domain/csv_parser.dart';

void main() {
  test('simple rows, CRLF and LF', () {
    expect(parseCsv('a,b\r\nc,d\n'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('quoted fields with commas, quotes and newlines', () {
    final rows = parseCsv('"Akram, Sahib","say ""hi""","line1\nline2"\n');
    expect(rows, [
      ['Akram, Sahib', 'say "hi"', 'line1\nline2'],
    ]);
  });

  test('blank lines are dropped and fields are trimmed', () {
    expect(parseCsv(' a , b \n\n , \nc,d'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('delimiter is detected: semicolon, tab, pipe', () {
    expect(detectDelimiter('a;b;c\n1;2;3'), ';');
    expect(detectDelimiter('a\tb\n1\t2'), '\t');
    expect(detectDelimiter('a|b|c'), '|');
    expect(detectDelimiter('"a,b";c'), ';');
    expect(parseCsv('a;b\n1;2'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('last row without a newline is kept', () {
    expect(parseCsv('a,b\nc,d'), hasLength(2));
  });

  test('empty text gives no rows', () {
    expect(parseCsv(''), isEmpty);
  });

  group('decodeTableBytes', () {
    test('UTF-8 with BOM', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('a,b')]);
      expect(decodeTableBytes(bytes), 'a,b');
    });

    test('UTF-16 little endian with BOM', () {
      final units = 'a,b'.codeUnits;
      final bytes = Uint8List.fromList([
        0xFF,
        0xFE,
        for (final u in units) ...[u & 0xFF, u >> 8],
      ]);
      expect(decodeTableBytes(bytes), 'a,b');
    });

    test('Urdu text survives UTF-8', () {
      final urdu = String.fromCharCodes([0x0627, 0x06A9, 0x0631, 0x0645]);
      expect(decodeTableBytes(Uint8List.fromList(utf8.encode(urdu))), urdu);
    });
  });
}
