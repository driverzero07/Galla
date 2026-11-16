import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_providers.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/phone.dart';
import '../data/secure_store.dart';
import '../data/shop_repository.dart';
import 'auth_state.dart';
import 'pin_hasher.dart';

final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());
final clockProvider = Provider<Clock>((ref) => systemClock);

/// Default auto-lock delay when no setting has been read yet.
const defaultPinLockMinutes = 5;

class AuthController extends Notifier<AuthState> {
  DateTime? _backgroundedAt;
  String? _shopId;

  SecureStore get _store => ref.read(secureStoreProvider);
  PinHasher get _hasher => ref.read(pinHasherProvider);

  @override
  AuthState build() {
    unawaited(Future.microtask(_restore));
    return const AuthLoading();
  }

  Future<void> _restore() async {
    final phone = await _store.read(SecureKeys.phone);
    final pinHash = await _store.read(SecureKeys.pinHash);
    final shopId = await _store.read(SecureKeys.shopId);
    if (phone == null || pinHash == null || shopId == null) {
      state = const AuthNeedsSetup();
    } else {
      _shopId = shopId;
      state = AuthLocked(phone: phone);
    }
  }

  /// Daily login: works fully offline. Returns true when phone and PIN match.
  Future<bool> unlock({required String phoneInput, required String pin}) async {
    final storedPhone = await _store.read(SecureKeys.phone);
    final pinHash = await _store.read(SecureKeys.pinHash);
    final shopId = await _store.read(SecureKeys.shopId);
    if (storedPhone == null || pinHash == null || shopId == null) {
      state = const AuthNeedsSetup();
      return false;
    }
    final normalized = normalizePkPhone(phoneInput);
    if (normalized == null || normalized != storedPhone) return false;
    if (!_hasher.verify(pin, pinHash)) return false;
    _shopId = shopId;
    state = AuthUnlocked(shopId: shopId, phone: storedPhone);
    return true;
  }

  /// Final step of first-time setup (after OTP succeeded): stores the PIN
  /// hash, creates the shop rows and unlocks.
  Future<void> completeSetup({
    required String shopId,
    required String phone,
    required String shopName,
    required String pin,
  }) async {
    await ref.read(shopRepositoryProvider).createShop(
          shopId: shopId,
          shopName: shopName,
          phone: phone,
        );
    await _store.write(SecureKeys.pinHash, _hasher.hash(pin));
    await _store.write(SecureKeys.phone, phone);
    await _store.write(SecureKeys.shopId, shopId);
    _shopId = shopId;
    state = AuthUnlocked(shopId: shopId, phone: phone);
  }

  /// Restore on a new phone: the shop rows were already pulled from the
  /// server, so only the PIN and identity are stored here.
  Future<void> completeRestore({
    required String shopId,
    required String phone,
    required String pin,
  }) async {
    await _store.write(SecureKeys.pinHash, _hasher.hash(pin));
    await _store.write(SecureKeys.phone, phone);
    await _store.write(SecureKeys.shopId, shopId);
    _shopId = shopId;
    state = AuthUnlocked(shopId: shopId, phone: phone);
  }

  void lock() {
    final current = state;
    if (current is AuthUnlocked) {
      state = AuthLocked(phone: current.phone);
    }
  }

  /// Call when the app goes to the background.
  void onBackgrounded() {
    if (state is AuthUnlocked) {
      _backgroundedAt = ref.read(clockProvider)();
    }
  }

  /// Call when the app returns to the foreground. Locks if it was away for
  /// at least the lock delay (default 5 minutes).
  Future<void> onForegrounded() async {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || state is! AuthUnlocked) return;
    final minutes = await _lockMinutes();
    final away = ref.read(clockProvider)().difference(since);
    if (away >= Duration(minutes: minutes) && state is AuthUnlocked) {
      lock();
    }
  }

  Future<int> _lockMinutes() async {
    final shopId = _shopId;
    if (shopId == null) return defaultPinLockMinutes;
    try {
      final settings =
          await ref.read(appDatabaseProvider).shopDao.settingsFor(shopId);
      return settings?.pinLockMinutes ?? defaultPinLockMinutes;
    } catch (_) {
      return defaultPinLockMinutes;
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
