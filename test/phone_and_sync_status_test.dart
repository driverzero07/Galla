import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/sync/sync_status.dart';
import 'package:galla/core/utils/phone.dart';

void main() {
  group('normalizePkPhone', () {
    test('accepts common local and international forms', () {
      expect(normalizePkPhone('0300 1234567'), '+923001234567');
      expect(normalizePkPhone('0300-1234567'), '+923001234567');
      expect(normalizePkPhone('923001234567'), '+923001234567');
      expect(normalizePkPhone('+92 300 1234567'), '+923001234567');
      expect(normalizePkPhone('00923001234567'), '+923001234567');
    });

    test('rejects invalid numbers', () {
      expect(normalizePkPhone(''), isNull);
      expect(normalizePkPhone('12345'), isNull);
      expect(normalizePkPhone('0200 1234567'), isNull);
    });

    test('displayPkPhone round trips', () {
      expect(displayPkPhone('+923001234567'), '0300 1234567');
    });
  });

  group('deriveSyncStatus (the three chip states)', () {
    test('nothing pending and online: all saved', () {
      expect(deriveSyncStatus(online: true, pending: 0), isA<SyncAllSaved>());
    });

    test('offline: data is saved on the phone', () {
      expect(deriveSyncStatus(online: false, pending: 0), isA<SyncOffline>());
      expect(deriveSyncStatus(online: false, pending: 5), isA<SyncOffline>());
    });

    test('online with pending changes shows the count', () {
      final s = deriveSyncStatus(online: true, pending: 3);
      expect(s, isA<SyncPending>());
      expect((s as SyncPending).count, 3);
    });
  });
}
