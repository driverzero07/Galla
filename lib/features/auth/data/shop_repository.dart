import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';

/// Deterministic id of the system "Naqad customer" row for a shop. Being
/// deterministic, two phones logged into the same shop agree on it and the
/// row can never be duplicated by sync.
String naqadCustomerId(String shopId) =>
    const Uuid().v5(Namespace.url.value, 'galla-naqad:$shopId');

const naqadCustomerName = 'Naqad customer';

class ShopRepository {
  ShopRepository(this._db);

  final AppDatabase _db;

  /// First-run setup: creates the shop, its settings row and the system
  /// Naqad customer in one transaction, all queued for sync.
  Future<void> createShop({
    required String shopId,
    required String shopName,
    required String phone,
    String? ownerName,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    return writeWithOutbox(_db, (outbox) async {
      final shop = await _db.into(_db.shops).insertReturning(
            ShopsCompanion.insert(
              id: shopId,
              shopId: shopId,
              name: shopName,
              phone: phone,
              ownerName: Value(ownerName),
              createdAt: stamp,
              updatedAt: stamp,
            ),
            mode: InsertMode.insertOrReplace,
          );
      outbox.record(
          table: 'shops',
          rowId: shop.id,
          payload: shop.toJson(),
          op: OutboxOp.insert);

      final naqad = await _db.into(_db.customers).insertReturning(
            CustomersCompanion.insert(
              id: naqadCustomerId(shopId),
              shopId: shopId,
              name: naqadCustomerName,
              createdAt: stamp,
              updatedAt: stamp,
            ),
            mode: InsertMode.insertOrReplace,
          );
      outbox.record(
          table: 'customers',
          rowId: naqad.id,
          payload: naqad.toJson(),
          op: OutboxOp.insert);

      final settings = await _db.into(_db.appSettings).insertReturning(
            AppSettingsCompanion.insert(
              id: shopId,
              shopId: shopId,
              createdAt: stamp,
              updatedAt: stamp,
            ),
            mode: InsertMode.insertOrReplace,
          );
      outbox.record(
          table: 'settings',
          rowId: settings.id,
          payload: settings.toJson(),
          op: OutboxOp.insert);
    }, now: () => stamp);
  }

  Future<Shop?> shopById(String shopId) => _db.shopDao.shopById(shopId);
}

final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) => ShopRepository(ref.watch(appDatabaseProvider)),
);
