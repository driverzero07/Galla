import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;


/// Pakistan has no daylight saving, so a fixed zone name is enough and needs
/// no extra plugin to ask the phone for its zone.
const notificationZone = 'Asia/Karachi';
const notificationHour = 9;
const _notificationId = 9001;
const _channelId = 'low_stock';

/// The next 9:00 in Karachi strictly after [now].
tz.TZDateTime nextNineAm(tz.TZDateTime now) {
  var t = tz.TZDateTime(now.location, now.year, now.month, now.day,
      notificationHour);
  if (!t.isAfter(now)) {
    t = tz.TZDateTime(now.location, now.year, now.month, now.day + 1,
        notificationHour);
  }
  return t;
}

/// Words for the notification, resolved from the ARB files by the caller.
class LowStockTexts {
  const LowStockTexts({
    required this.title,
    required this.body,
    required this.channelName,
    required this.channelDescription,
  });
  final String title;
  final String body;
  final String channelName;
  final String channelDescription;
}

/// One notification a day at 9 am while something is low on stock; none
/// otherwise. [sync] is safe to call as often as stock changes.
abstract class LowStockNotifier {
  Future<void> sync({required bool anyLow, required LowStockTexts texts});
}

class LocalLowStockNotifier implements LowStockNotifier {
  LocalLowStockNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  bool? _scheduled;
  bool _askedPermission = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(notificationZone));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  @override
  Future<void> sync(
      {required bool anyLow, required LowStockTexts texts}) async {
    // Nothing to do when the state did not change since the last call.
    if (_scheduled == anyLow) return;
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (!anyLow) {
        await _plugin.cancel(_notificationId);
        _scheduled = false;
        return;
      }
      if (!_askedPermission) {
        _askedPermission = true;
        await android?.requestNotificationsPermission();
      }
      final zone = tz.getLocation(notificationZone);
      await _plugin.zonedSchedule(
        _notificationId,
        texts.title,
        texts.body,
        nextNineAm(tz.TZDateTime.now(zone)),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            texts.channelName,
            channelDescription: texts.channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        // Inexact: no special alarm permission, fires around 9 am.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Same time every day until cancelled.
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      _scheduled = true;
    } catch (e) {
      // A notification problem must never break the app.
      if (kDebugMode) debugPrint('low stock notification error: $e');
    }
  }
}

final lowStockNotifierProvider =
    Provider<LowStockNotifier>((ref) => LocalLowStockNotifier());
