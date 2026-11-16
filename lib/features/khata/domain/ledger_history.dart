import '../../../core/db/constants.dart';
import '../../../core/db/daos/khata_dao.dart';

/// One line of a customer or supplier history, newest first on screen.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.balanceAfter,
    this.refId,
    this.note,
    this.docNo,
    this.itemsText,
    this.paidNote,
  });

  final String id;

  /// A [CustomerLedgerType] or [SupplierLedgerType] value.
  final String type;

  /// Signed paisa as stored in the ledger.
  final int amount;
  final DateTime date;

  /// Running balance right after this entry (ledger order).
  final int balanceAfter;
  final String? refId;
  final String? note;

  /// Bill or purchase number when the entry belongs to one.
  final String? docNo;

  /// "Cheeni, Chai patti, Atta" for bill / purchase rows.
  final String? itemsText;

  /// Purchases only: how much was paid on the spot (not in the ledger).
  final int? paidNote;

  bool get isDocument =>
      type == CustomerLedgerType.saleCredit ||
      type == SupplierLedgerType.purchaseCredit;
}

class History {
  const History(this.entries, this.balance);

  /// Newest first.
  final List<HistoryEntry> entries;

  /// SUM of the ledger (also the balance after the newest entry).
  final int balance;
}

/// Oldest-first order used for running balances: entry date, then the time
/// the row was written, then id so the order is always the same.
int compareLedger(RawLedger a, RawLedger b) {
  final d = a.date.compareTo(b.date);
  if (d != 0) return d;
  final c = a.createdAt.compareTo(b.createdAt);
  if (c != 0) return c;
  return a.id.compareTo(b.id);
}

/// Adds a running balance to raw ledger rows. The final balance always
/// equals the plain SUM of the amounts, whatever the order.
/// [describe] lets the caller attach bill / purchase details by ref id.
History buildHistory(
  List<RawLedger> rows, {
  ({String? docNo, String? itemsText, int? paidNote}) Function(RawLedger row)?
      describe,
}) {
  final sorted = [...rows]..sort(compareLedger);
  var running = 0;
  final out = <HistoryEntry>[];
  for (final r in sorted) {
    running += r.amount;
    final d = describe?.call(r);
    out.add(HistoryEntry(
      id: r.id,
      type: r.type,
      amount: r.amount,
      date: r.date,
      balanceAfter: running,
      refId: r.refId,
      note: r.note,
      docNo: d?.docNo,
      itemsText: d?.itemsText,
      paidNote: d?.paidNote,
    ));
  }
  return History(out.reversed.toList(), running);
}

/// Item names for a history row: first three, then "...".
String joinItemNames(List<String> names, {int max = 3}) {
  if (names.length <= max) return names.join(', ');
  return '${names.take(max).join(', ')}...';
}

/// Whole calendar days between [date] and [now] (0 = today).
int daysAgo(DateTime now, DateTime date) {
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(date.year, date.month, date.day);
  final d = a.difference(b).inDays;
  return d < 0 ? 0 : d;
}

/// Customer list order: highest balance first, or most recent activity.
enum KhataSort { highest, recent }

List<T> sortParties<T>(
  List<T> rows,
  KhataSort sort, {
  required int Function(T) balance,
  required DateTime? Function(T) last,
  required String Function(T) name,
}) {
  final out = [...rows];
  out.sort((a, b) {
    if (sort == KhataSort.recent) {
      final la = last(a), lb = last(b);
      if (la != null && lb != null) {
        final c = lb.compareTo(la);
        if (c != 0) return c;
      } else if (la != null) {
        return -1;
      } else if (lb != null) {
        return 1;
      }
    } else {
      final c = balance(b).compareTo(balance(a));
      if (c != 0) return c;
    }
    return name(a).toLowerCase().compareTo(name(b).toLowerCase());
  });
  return out;
}

/// Lena card: total of what customers owe (advances are not netted off, they
/// are shown on their own rows) and how many customers owe.
({int total, int owing}) lenaSummary(Iterable<int> balances) {
  var total = 0;
  var owing = 0;
  for (final b in balances) {
    if (b > 0) {
      total += b;
      owing++;
    }
  }
  return (total: total, owing: owing);
}
