import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'shop_dao.g.dart';

@DriftAccessor(tables: [Shops, AppSettings])
class ShopDao extends DatabaseAccessor<AppDatabase> with _$ShopDaoMixin {
  ShopDao(super.db);

  Future<Shop?> shopById(String id) =>
      (select(shops)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Shop?> watchShop(String id) =>
      (select(shops)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<SettingsRow?> settingsFor(String shopId) => (select(appSettings)
        ..where((t) => t.shopId.equals(shopId)))
      .getSingleOrNull();

  Stream<SettingsRow?> watchSettings(String shopId) => (select(appSettings)
        ..where((t) => t.shopId.equals(shopId)))
      .watchSingleOrNull();
}
