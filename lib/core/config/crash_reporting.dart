import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash reporting is OFF unless a Sentry DSN is passed at build time:
/// `--dart-define=SENTRY_DSN=https://...`. The DSN is not a secret.
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Removes everything that could hold customer or shop data before an event
/// leaves the phone. Only the error TYPE, the stack trace, the app version
/// and the device model/OS stay. Exception messages are dropped because they
/// can contain SQL values or names.
SentryEvent? scrubEvent(SentryEvent event) {
  // Built from scratch (an allow-list) so a field added to the SDK later can
  // never leak by default.
  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    platform: event.platform,
    release: event.release,
    dist: event.dist,
    environment: event.environment,
    level: event.level,
    sdk: event.sdk,
    contexts: event.contexts, // device model, OS, app version
    debugMeta: event.debugMeta,
    threads: event.threads,
    exceptions: [
      for (final e in event.exceptions ?? const <SentryException>[])
        e.copyWith(value: ''),
    ],
  );
}

/// Starts Sentry around [appRunner], or just runs the app when no DSN is set
/// (debug builds, or until the owner creates a Sentry project).
Future<void> runWithCrashReporting(Future<void> Function() appRunner) async {
  if (sentryDsn.isEmpty || kDebugMode) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (o) {
      o.dsn = sentryDsn;
      o.sendDefaultPii = false;
      o.maxBreadcrumbs = 0;
      o.attachScreenshot = false;
      o.attachViewHierarchy = false;
      o.enableUserInteractionBreadcrumbs = false;
      o.enableAutoNativeBreadcrumbs = false;
      o.tracesSampleRate = 0;
      o.beforeSend = (event, hint) => scrubEvent(event);
    },
    appRunner: appRunner,
  );
}
