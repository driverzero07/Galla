import '../../../core/db/daos/inventory_dao.dart';

/// Today's numbers for the Home cards. All paisa.
class TodaySummary {
  const TodaySummary({
    this.bills = 0,
    this.total = 0,
    this.paid = 0,
    this.cost = 0,
  });

  /// Active bills only (cancelled ones are left out).
  final int bills;

  /// Sum of bill totals, after discounts.
  final int total;

  /// Money received at the counter (paid amount of every bill).
  final int paid;

  /// Sum of qty x cost snapshot over the bill lines.
  final int cost;

  /// Cash chip: what was paid on the spot.
  int get cash => paid;

  /// Udhaar chip: what was left unpaid. cash + udhaar always equals total.
  int get udhaar => total - paid;

  /// Part 0 rule 9: SUM(line_total) - SUM(qty x cost_snapshot) - discounts
  /// for active bills. Bill total is already line totals minus discount.
  int get profit => total - cost;
}

/// Same rounding as bills: half a paisa rounds up.
int costOfLine(int qtyMilli, int costPaisa) => (qtyMilli * costPaisa + 500) ~/ 1000;

/// Start of the local day [now] is in, and of the next day.
({DateTime from, DateTime to}) dayRange(DateTime now) {
  final from = DateTime(now.year, now.month, now.day);
  return (from: from, to: DateTime(now.year, now.month, now.day + 1));
}

/// How long until the day changes (never zero).
Duration untilNextDay(DateTime now) {
  final d = dayRange(now).to.difference(now);
  return d.inSeconds <= 0 ? const Duration(seconds: 1) : d;
}

/// The lowest [limit] items for the Home card: least stock first (negative
/// stock is the lowest), then by name.
List<ItemWithStock> lowestStock(List<ItemWithStock> low, {int limit = 3}) {
  final sorted = [...low]..sort((a, b) {
      final c = a.stock.compareTo(b.stock);
      if (c != 0) return c;
      return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
    });
  return sorted.take(limit).toList();
}

/// One entry in the bell's alert list.
sealed class AlertEntry {
  const AlertEntry();
}

/// [count] items are at or below their low-stock level.
class LowStockAlert extends AlertEntry {
  const LowStockAlert(this.items);
  final List<ItemWithStock> items;
  int get count => items.length;
}

/// Offline with changes that could not be sent yet.
class SyncAlert extends AlertEntry {
  const SyncAlert(this.pending);
  final int pending;
}

List<AlertEntry> buildAlerts({
  required List<ItemWithStock> lowItems,
  required bool online,
  required int pending,
}) =>
    [
      if (lowItems.isNotEmpty) LowStockAlert(lowItems),
      if (!online && pending > 0) SyncAlert(pending),
    ];

/// Number on the bell: one per low item plus one for a sync problem.
int alertCount(List<AlertEntry> alerts) {
  var n = 0;
  for (final a in alerts) {
    n += switch (a) {
      LowStockAlert(:final count) => count,
      SyncAlert() => 1,
    };
  }
  return n;
}
