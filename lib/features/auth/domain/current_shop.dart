import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/db_providers.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// The shop of the logged-in owner, live from the local database.
final currentShopProvider = StreamProvider<Shop?>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthUnlocked) return Stream.value(null);
  return ref.watch(appDatabaseProvider).shopDao.watchShop(auth.shopId);
});

/// Id of the logged-in shop. Throws while the app is locked, so no write can
/// ever run without a shop.
final shopIdProvider = Provider<String>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is AuthUnlocked) return auth.shopId;
  throw StateError('No shop: app is locked');
});
