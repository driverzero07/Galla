import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/core/db/daos/khata_dao.dart';
import 'package:galla/features/khata/domain/ledger_history.dart';

RawLedger row(String id, int amount, DateTime date,
        {String type = CustomerLedgerType.manualUdhaar, DateTime? created}) =>
    (
      id: id,
      type: type,
      amount: amount,
      date: date,
      createdAt: created ?? date,
      refId: null,
      note: null,
    );

void main() {
  final d1 = DateTime(2026, 11, 1, 10);
  final d2 = DateTime(2026, 11, 5, 10);
  final d3 = DateTime(2026, 11, 9, 10);

  group('buildHistory', () {
    test('running balance, newest first; final balance = SUM', () {
      final h = buildHistory([
        row('c', -2000, d3, type: CustomerLedgerType.paymentReceived),
        row('a', 1000, d1),
        row('b', 3000, d2),
      ]);
      expect(h.entries.map((e) => e.id), ['c', 'b', 'a']);
      expect(h.entries.map((e) => e.balanceAfter), [2000, 4000, 1000]);
      expect(h.balance, 2000);
    });

    test('advance gives a negative balance', () {
      final h = buildHistory([
        row('a', 1000, d1),
        row('b', -5000, d2, type: CustomerLedgerType.paymentReceived),
      ]);
      expect(h.balance, -4000);
      expect(h.entries.first.balanceAfter, -4000);
    });

    test('empty history is zero', () {
      final h = buildHistory(const []);
      expect(h.entries, isEmpty);
      expect(h.balance, 0);
    });

    test('same date keeps write order; order is stable', () {
      final t = DateTime(2026, 11, 9);
      final h = buildHistory([
        row('late', 100, t, created: DateTime(2026, 11, 9, 12)),
        row('early', 200, t, created: DateTime(2026, 11, 9, 8)),
      ]);
      expect(h.entries.map((e) => e.id), ['late', 'early']);
      expect(h.entries.last.balanceAfter, 200);
    });

    test('describe attaches bill details', () {
      final h = buildHistory([row('a', 1000, d1)],
          describe: (r) => (docNo: 'ABC-1', itemsText: 'Cheeni', paidNote: 5));
      expect(h.entries.single.docNo, 'ABC-1');
      expect(h.entries.single.itemsText, 'Cheeni');
      expect(h.entries.single.paidNote, 5);
    });
  });

  test('joinItemNames shortens long lists', () {
    expect(joinItemNames(['a', 'b']), 'a, b');
    expect(joinItemNames(['a', 'b', 'c', 'd']), 'a, b, c...');
  });

  test('daysAgo counts calendar days', () {
    final now = DateTime(2026, 11, 14, 1);
    expect(daysAgo(now, DateTime(2026, 11, 13, 23)), 1);
    expect(daysAgo(now, DateTime(2026, 11, 14, 0)), 0);
    expect(daysAgo(now, DateTime(2026, 11, 15)), 0);
  });

  group('khata list', () {
    final List<({String name, int bal, DateTime? last})> rows = [
      (name: 'Bilal', bal: 500, last: DateTime(2026, 11, 10)),
      (name: 'Akram', bal: 900, last: DateTime(2026, 11, 1)),
      (name: 'Zubair', bal: 900, last: null),
      (name: 'Sana', bal: -300, last: DateTime(2026, 11, 12)),
    ];
    List<String> sorted(KhataSort s) => sortParties(rows, s,
            balance: (r) => r.bal, last: (r) => r.last, name: (r) => r.name)
        .map((r) => r.name)
        .toList();

    test('highest balance first, ties by name', () {
      expect(sorted(KhataSort.highest), ['Akram', 'Zubair', 'Bilal', 'Sana']);
    });
    test('most recent first, no activity last', () {
      expect(sorted(KhataSort.recent), ['Sana', 'Bilal', 'Akram', 'Zubair']);
    });
    test('lena counts only customers who owe', () {
      final l = lenaSummary(rows.map((r) => r.bal));
      expect(l.total, 2300);
      expect(l.owing, 3);
    });
  });
}
