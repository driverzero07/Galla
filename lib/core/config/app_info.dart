/// Keep in step with `version:` in pubspec.yaml (a test checks this).
abstract final class AppInfo {
  static const version = '1.0.0';

  /// Public privacy policy page (see docs/release/privacy_policy.md). Pass
  /// with --dart-define=PRIVACY_URL=https://... ; the link is hidden if empty.
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');
}
