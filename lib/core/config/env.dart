/// Build-time configuration. Pass with
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
/// Nothing here is a secret: the anon key is safe to ship because Supabase
/// row level security protects the data.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Demo data and the fake OTP provider are available only when this is on
  /// (always off in release builds; see main.dart).
  static const enableDebugTools =
      bool.fromEnvironment('GALLA_DEBUG_TOOLS', defaultValue: true);
}
