import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/notifications/low_stock_notifier.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location karachi;

  setUpAll(() {
    tzdata.initializeTimeZones();
    karachi = tz.getLocation(notificationZone);
  });

  tz.TZDateTime at(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) =>
      tz.TZDateTime(karachi, y, m, d, h, min, s);

  group('nextNineAm', () {
    test('before 9 am: today', () {
      expect(nextNineAm(at(2026, 11, 14, 8, 59)), at(2026, 11, 14, 9));
      expect(nextNineAm(at(2026, 11, 14, 0, 0)), at(2026, 11, 14, 9));
    });

    test('at or after 9 am: tomorrow, so it never fires twice in a day', () {
      expect(nextNineAm(at(2026, 11, 14, 9)), at(2026, 11, 15, 9));
      expect(nextNineAm(at(2026, 11, 14, 9, 0, 1)), at(2026, 11, 15, 9));
      expect(nextNineAm(at(2026, 11, 14, 23, 59)), at(2026, 11, 15, 9));
    });

    test('month and year ends', () {
      expect(nextNineAm(at(2026, 11, 30, 10)), at(2026, 12, 1, 9));
      expect(nextNineAm(at(2026, 12, 31, 10)), at(2027, 1, 1, 9));
    });

    test('result is in the Karachi zone at 09:00 local', () {
      final t = nextNineAm(at(2026, 11, 14, 12));
      expect(t.location.name, 'Asia/Karachi');
      expect(t.hour, 9);
      expect(t.minute, 0);
      expect(t.timeZoneOffset, const Duration(hours: 5));
    });
  });

  test('a notification problem never throws into the app', () async {
    final notifier = LocalLowStockNotifier();
    await notifier.sync(
      anyLow: true,
      texts: const LowStockTexts(
          title: 't', body: 'b', channelName: 'c', channelDescription: 'd'),
    );
    await notifier.sync(
      anyLow: false,
      texts: const LowStockTexts(
          title: 't', body: 'b', channelName: 'c', channelDescription: 'd'),
    );
  });
}
