import 'dart:math';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'device_state_dao.g.dart';

/// Per-device settings that must never sync (bill prefix/sequence, draft).
@DriftAccessor(tables: [DeviceState])
class DeviceStateDao extends DatabaseAccessor<AppDatabase>
    with _$DeviceStateDaoMixin {
  DeviceStateDao(super.db);

  Future<String?> get(String key) async {
    final row = await (select(deviceState)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => into(deviceState).insertOnConflictUpdate(
        DeviceStateCompanion.insert(key: key, value: value),
      );

  Future<void> remove(String key) =>
      (delete(deviceState)..where((t) => t.key.equals(key))).go();

  static const _prefixAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const prefixKey = 'bill_prefix';

  /// Next document number "XXX-n": a per-device 3 character prefix (shared by
  /// bills and purchases) plus a running number kept under [seqKey]. Call it
  /// inside the saving transaction so a failed save does not burn a number.
  Future<String> nextNumber(String seqKey, Random random) async {
    var prefix = await get(prefixKey);
    if (prefix == null) {
      prefix = List.generate(
        3,
        (_) => _prefixAlphabet[random.nextInt(_prefixAlphabet.length)],
      ).join();
      await set(prefixKey, prefix);
    }
    final seq = (int.tryParse(await get(seqKey) ?? '') ?? 0) + 1;
    await set(seqKey, '$seq');
    return '$prefix-$seq';
  }
}
