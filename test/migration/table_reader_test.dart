import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galla/features/migration/data/table_reader.dart';

void main() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  test('reads csv and pads short rows', () {
    final t = readTable(b('a,b,c\n1,2\n'), 'x.csv');
    expect(t, [
      ['a', 'b', 'c'],
      ['1', '2', ''],
    ]);
  });

  test('extension decides, case-insensitive', () {
    expect(readTable(b('a\tb'), 'X.TSV'), [
      ['a', 'b']
    ]);
  });

  test('.xls and others are unsupported', () {
    expect(() => readTable(b('x'), 'old.xls'),
        throwsA(isA<TableReadException>()));
    expect(() => readTable(b('x'), 'doc.pdf'),
        throwsA(isA<TableReadException>()));
  });

  test('empty file', () {
    expect(() => readTable(Uint8List(0), 'x.csv'),
        throwsA(isA<TableReadException>()));
  });

  test('broken xlsx is reported, not thrown raw', () {
    expect(() => readTable(b('not a zip'), 'x.xlsx'),
        throwsA(isA<TableReadException>()));
  });

  test('cellToText drops .0 on whole numbers', () {
    expect(cellToText(3400.0), '3400');
    expect(cellToText(12.5), '12.5');
    expect(cellToText(null), '');
    expect(cellToText('  Akram '), 'Akram');
  });
}
