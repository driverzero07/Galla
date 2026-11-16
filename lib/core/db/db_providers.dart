import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// The single local database. The UI reads and writes only this.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});
