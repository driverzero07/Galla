import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/env.dart';

class OtpException implements Exception {
  const OtpException(this.message);
  final String message;
  @override
  String toString() => 'OtpException: $message';
}

/// Sends and verifies the one-time code used at first setup. Kept behind an
/// interface so the provider can be swapped (SMS today, email OTP as a
/// temporary fallback) without touching the UI.
abstract class OtpProvider {
  /// [phoneE164] is like `+923001234567`.
  Future<void> sendOtp(String phoneE164);

  /// Returns the authenticated account id (becomes the shop id).
  /// Throws [OtpException] on a wrong or expired code.
  Future<String> verifyOtp(String phoneE164, String code);
}

/// Supabase phone OTP.
class SupabaseOtpProvider implements OtpProvider {
  SupabaseOtpProvider(this._client);

  final SupabaseClient _client;

  @override
  Future<void> sendOtp(String phoneE164) async {
    try {
      await _client.auth.signInWithOtp(phone: phoneE164);
    } on AuthException catch (e) {
      throw OtpException(e.message);
    }
  }

  @override
  Future<String> verifyOtp(String phoneE164, String code) async {
    try {
      final res = await _client.auth.verifyOTP(
        phone: phoneE164,
        token: code,
        type: OtpType.sms,
      );
      final user = res.user;
      if (user == null) throw const OtpException('No user returned');
      return user.id;
    } on AuthException catch (e) {
      throw OtpException(e.message);
    }
  }
}

/// Debug-only fake: any phone, code `123456`. Lets the app run before
/// Supabase is configured. Never used in release builds.
class DebugOtpProvider implements OtpProvider {
  static const code = '123456';

  @override
  Future<void> sendOtp(String phoneE164) async {}

  @override
  Future<String> verifyOtp(String phoneE164, String code) async {
    if (code != DebugOtpProvider.code) {
      throw const OtpException('Wrong code');
    }
    return const Uuid().v5(Namespace.url.value, 'galla-debug:$phoneE164');
  }
}

final otpProviderProvider = Provider<OtpProvider>((ref) {
  if (Env.supabaseConfigured) {
    return SupabaseOtpProvider(Supabase.instance.client);
  }
  if (kDebugMode && Env.enableDebugTools) return DebugOtpProvider();
  throw StateError(
    'Supabase is not configured. Pass SUPABASE_URL and SUPABASE_ANON_KEY '
    'with --dart-define.',
  );
});
