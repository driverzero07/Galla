import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart';
import '../../features/home/domain/dashboard.dart';

/// Start of the current local day. Emits again at midnight (and when the app
/// comes back to the foreground after midnight), so everything that watches
/// it rolls over to the new day by itself.
final dayStartProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  final controller = StreamController<DateTime>();
  Timer? timer;
  DateTime? last;

  void emitIfChanged() {
    final now = clock();
    final start = dayRange(now).from;
    if (last != start) {
      last = start;
      if (!controller.isClosed) controller.add(start);
    }
  }

  void schedule() {
    timer?.cancel();
    timer = Timer(untilNextDay(clock()) + const Duration(seconds: 1), () {
      emitIfChanged();
      schedule();
    });
  }

  emitIfChanged();
  schedule();

  // Timers can sleep with the phone; check again when the app wakes up.
  final lifecycle = AppLifecycleListener(onResume: () {
    emitIfChanged();
    schedule();
  });

  ref.onDispose(() {
    timer?.cancel();
    lifecycle.dispose();
    controller.close();
  });
  return controller.stream;
});
