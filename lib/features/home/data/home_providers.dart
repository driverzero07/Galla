import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/daos/inventory_dao.dart';
import '../../../core/db/daos/khata_dao.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/connectivity.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/utils/day_start.dart';
import '../../auth/domain/current_shop.dart';
import '../../customers/data/party_repository.dart';
import '../../khata/domain/ledger_history.dart';
import '../domain/dashboard.dart';

/// Aj Ki Bikri / Munafa numbers, live.
final todaySummaryProvider =
    StreamProvider.autoDispose<TodaySummary>((ref) {
  final shopId = ref.watch(shopIdProvider);
  final from = ref.watch(dayStartProvider).valueOrNull;
  if (from == null) return const Stream<TodaySummary>.empty();
  final to = dayRange(from).to;
  return ref
      .watch(appDatabaseProvider)
      .salesDao
      .watchDaySummary(shopId, from, to)
      .map((r) => TodaySummary(
          bills: r.bills, total: r.total, paid: r.paid, cost: r.cost));
});

/// Every visible item at or below its level, in the DAO's name order.
final lowItemsProvider =
    StreamProvider.autoDispose<List<ItemWithStock>>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref
      .watch(appDatabaseProvider)
      .inventoryDao
      .watchItems(shopId, lowOnly: true);
});

/// How many visible items exist at all (first-day empty state).
final itemCountProvider = StreamProvider.autoDispose<int>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref
      .watch(appDatabaseProvider)
      .inventoryDao
      .watchItems(shopId)
      .map((l) => l.length);
});

/// Lena / Dena card values: sum of positive balances and how many owe.
typedef OwedSummary = ({int total, int count});

OwedSummary _owed(List<PartyRow> rows) {
  final s = lenaSummary(rows.map((r) => r.balance));
  return (total: s.total, count: s.owing);
}

final lenaProvider = Provider.autoDispose<OwedSummary>((ref) {
  final rows = ref
          .watch(partyListProvider(
              (kind: PartyKind.customer, query: '', showHidden: false)))
          .valueOrNull ??
      const <PartyRow>[];
  return _owed(rows);
});

final denaProvider = Provider.autoDispose<OwedSummary>((ref) {
  final rows = ref
          .watch(partyListProvider(
              (kind: PartyKind.supplier, query: '', showHidden: false)))
          .valueOrNull ??
      const <PartyRow>[];
  return _owed(rows);
});

/// The bell's list.
final alertsProvider = Provider.autoDispose<List<AlertEntry>>((ref) {
  final low = ref.watch(lowItemsProvider).valueOrNull ?? const [];
  final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
  final pending = ref.watch(pendingChangesProvider).valueOrNull ?? 0;
  return buildAlerts(lowItems: low, online: online, pending: pending);
});
