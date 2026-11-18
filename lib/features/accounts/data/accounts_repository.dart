import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';

/// The shop's money picture, all paisa and all derived from the books.
class ShopAccounts {
  const ShopAccounts({
    required this.openingCash,
    required this.cashSales,
    required this.paymentsReceived,
    required this.cashRefunds,
    required this.purchasePaid,
    required this.supplierPaid,
    required this.stockValue,
    required this.customersOwe,
    required this.weOwe,
  });

  final int openingCash;

  /// Money taken at the counter on active bills.
  final int cashSales;

  /// Customer khata payments received.
  final int paymentsReceived;

  /// Cash handed back on returns.
  final int cashRefunds;

  /// Paid to suppliers while buying stock.
  final int purchasePaid;

  /// Paid to suppliers later ("paisay diye").
  final int supplierPaid;

  /// Stock on hand at cost price.
  final int stockValue;

  /// Net customer khata (lena).
  final int customersOwe;

  /// Net supplier khata (dena).
  final int weOwe;

  int get cashIn => openingCash + cashSales + paymentsReceived;
  int get cashOut => cashRefunds + purchasePaid + supplierPaid;

  /// Cash in the drawer right now.
  int get cashInHand => cashIn - cashOut;

  /// What the shop is worth today: cash + stock + lena - dena.
  int get shopValue => cashInHand + stockValue + customersOwe - weOwe;
}

class AccountsRepository {
  AccountsRepository(this._db, this._shopId, this._now);

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;

  static const _tables = {
    'shops',
    'sales',
    'sale_returns',
    'purchases',
    'customer_ledger',
    'supplier_ledger',
    'stock_movements',
    'items',
  };

  /// Everything in one query so the numbers always agree with each other.
  static const _sql = '''
SELECT
  COALESCE((SELECT opening_cash FROM shops WHERE id = ?1), 0) AS opening_cash,
  COALESCE((SELECT SUM(paid_amount) FROM sales
            WHERE shop_id = ?1 AND status = 'active'), 0) AS cash_sales,
  COALESCE((SELECT -SUM(amount) FROM customer_ledger
            WHERE shop_id = ?1 AND type = 'payment_received'), 0) AS received,
  COALESCE((SELECT SUM(r.cash_refund) FROM sale_returns r
            JOIN sales s ON s.id = r.sale_id
            WHERE r.shop_id = ?1 AND s.status = 'active'), 0) AS refunds,
  COALESCE((SELECT SUM(paid_amount) FROM purchases
            WHERE shop_id = ?1 AND status = 'active'), 0) AS purchase_paid,
  COALESCE((SELECT -SUM(amount) FROM supplier_ledger
            WHERE shop_id = ?1 AND type = 'payment_made'), 0) AS supplier_paid,
  COALESCE((SELECT SUM((st.stock * i.cost_price + 500) / 1000)
            FROM items i
            JOIN (SELECT item_id, SUM(qty) AS stock FROM stock_movements
                  WHERE shop_id = ?1 GROUP BY item_id) st
              ON st.item_id = i.id
            WHERE i.shop_id = ?1 AND st.stock > 0), 0) AS stock_value,
  COALESCE((SELECT SUM(amount) FROM customer_ledger
            WHERE shop_id = ?1), 0) AS customers_owe,
  COALESCE((SELECT SUM(amount) FROM supplier_ledger
            WHERE shop_id = ?1), 0) AS we_owe
''';

  static ShopAccounts _read(QueryRow r) => ShopAccounts(
        openingCash: r.read<int>('opening_cash'),
        cashSales: r.read<int>('cash_sales'),
        paymentsReceived: r.read<int>('received'),
        cashRefunds: r.read<int>('refunds'),
        purchasePaid: r.read<int>('purchase_paid'),
        supplierPaid: r.read<int>('supplier_paid'),
        stockValue: r.read<int>('stock_value'),
        customersOwe: r.read<int>('customers_owe'),
        weOwe: r.read<int>('we_owe'),
      );

  Stream<ShopAccounts> watch() {
    final id = _shopId();
    return _db
        .customSelect(_sql,
            variables: [Variable<String>(id)],
            readsFrom: {
              _db.shops,
              _db.sales,
              _db.saleReturns,
              _db.purchases,
              _db.customerLedger,
              _db.supplierLedger,
              _db.stockMovements,
              _db.items,
            })
        .watchSingle()
        .map(_read);
  }

  Future<ShopAccounts> snapshot() async {
    final row = await _db
        .customSelect(_sql, variables: [Variable<String>(_shopId())])
        .getSingle();
    return _read(row);
  }

  Future<int> cashInHand() async => (await snapshot()).cashInHand;

  /// Cash in hand for use inside another repository's transaction, so a
  /// payment is checked against the same books it is about to be written to.
  static Future<int> cashInHandOf(AppDatabase db, String shopId) async {
    final row = await db
        .customSelect(_sql, variables: [Variable<String>(shopId)])
        .getSingle();
    return _read(row).cashInHand;
  }

  /// Sets the drawer cash the shop started with. Everything after it is
  /// derived, so changing this simply moves cash in hand by the difference.
  Future<void> setOpeningCash(int paisa) async {
    if (paisa < 0) throw ArgumentError('opening cash cannot be negative');
    final id = _shopId();
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await (_db.update(_db.shops)..where((t) => t.id.equals(id))).write(
        ShopsCompanion(openingCash: Value(paisa), updatedAt: Value(now)),
      );
      final shop = await _db.shopDao.shopById(id);
      if (shop != null) {
        outbox.record(
            table: 'shops',
            rowId: id,
            payload: shop.toJson(),
            op: OutboxOp.update);
      }
    }, now: () => now);
  }
}

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

final shopAccountsProvider = StreamProvider.autoDispose<ShopAccounts>((ref) {
  ref.watch(shopIdProvider);
  return ref.read(accountsRepositoryProvider).watch();
});
