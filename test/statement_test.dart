import 'package:flutter_test/flutter_test.dart';
import 'package:galla/features/khata/data/statement_service.dart';

void main() {
  final labels = StatementLabels(
    title: 'Khata statement',
    balanceLabel: 'Baqaya',
    advanceLabel: 'Advance',
    date: 'Tareekh',
    detail: 'Tafseel',
    amount: 'Raqam',
    balance: 'Baqaya',
    moreRows: (n) => 'Purani $n entries nahi dikhayi',
    thanks: 'Shukriya',
  );

  StatementData data({int balance = 3400, int rows = 3}) => StatementData(
        shopName: 'Test Store',
        partyName: 'Akram Sahib',
        partyPhone: '+923001234567',
        generatedAt: DateTime(2026, 11, 14),
        balance: balance,
        rows: [
          for (var i = 0; i < rows; i++)
            StatementRow(
              date: DateTime(2026, 11, 1 + i % 10),
              title: i.isEven ? 'Bill #A-$i' : 'Paisay mile',
              detail: i.isEven ? 'Cheeni, Atta' : null,
              amount: i.isEven ? 120000 : -200000,
              balance: 3400,
            ),
        ],
      );

  test('text has shop, party, rows with signs, and the baqaya', () {
    final t = buildStatementText(data(), labels);
    expect(t, contains('Test Store'));
    expect(t, contains('Akram Sahib'));
    expect(t, contains('Bill #A-0'));
    expect(t, contains('+ Rs 1,200'));
    expect(t, contains('- Rs 2,000'));
    expect(t, contains('Cheeni, Atta'));
    expect(t, contains('Baqaya: Rs 34'));
    expect(t, contains('Shukriya'));
  });

  test('advance is labelled as advance', () {
    final t = buildStatementText(data(balance: -5000), labels);
    expect(t, contains('Advance: Rs 50'));
    expect(t, isNot(contains('Baqaya: Rs')));
  });

  test('long history keeps the newest rows and says so', () {
    final t = buildStatementText(data(rows: 50), labels, maxRows: 40);
    expect(t, contains('Purani 10 entries nahi dikhayi'));
    expect(RegExp('Bill #A-').allMatches(t).length, 20);
  });

  test('PDF is built and starts with %PDF, also for many rows', () async {
    final small = await buildStatementPdf(data(), labels);
    expect(String.fromCharCodes(small.take(4)), '%PDF');
    final big = await buildStatementPdf(data(rows: 200), labels);
    expect(String.fromCharCodes(big.take(4)), '%PDF');
    expect(big.length, greaterThan(small.length));
  });
}
