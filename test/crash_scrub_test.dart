import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/config/crash_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('crash events carry no customer data', () {
    final event = SentryEvent(
      message: const SentryMessage('Akram owes Rs 3400'),
      user: SentryUser(id: 'u1', email: 'a@b.pk', username: 'Akram'),
      breadcrumbs: [Breadcrumb(message: 'tapped Akram Sahib')],
      extra: {'customer': 'Akram'},
      tags: {'phone': '+923001234567'},
      release: 'galla@1.0.0+1',
      exceptions: [
        SentryException(
            type: 'SqliteException',
            value: "UNIQUE constraint failed: customers.name 'Akram'"),
      ],
    );
    final clean = scrubEvent(event)!;
    expect(clean.user, isNull);
    expect(clean.message, isNull);
    expect(clean.breadcrumbs, anyOf(isNull, isEmpty));
    expect(clean.extra, anyOf(isNull, isEmpty));
    expect(clean.tags, anyOf(isNull, isEmpty));
    expect(clean.exceptions!.single.type, 'SqliteException');
    expect(clean.exceptions!.single.value, '');
    expect(clean.release, 'galla@1.0.0+1');
  });
}
