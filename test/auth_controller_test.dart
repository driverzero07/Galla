import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/app_database.dart';
import 'package:galla/core/db/db_providers.dart';
import 'package:galla/features/auth/data/secure_store.dart';
import 'package:galla/features/auth/domain/auth_controller.dart';
import 'package:galla/features/auth/domain/auth_state.dart';
import 'package:galla/features/auth/domain/pin_hasher.dart';
import 'package:galla/router/app_router.dart';

class _MemoryStore implements SecureStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late AppDatabase db;
  late _MemoryStore store;
  late DateTime clock;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = _MemoryStore();
    clock = DateTime(2026, 11, 13, 10);
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(store),
      pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10)),
      clockProvider.overrideWithValue(() => clock),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<AuthController> start() async {
    container.read(authControllerProvider); // build
    await Future<void>.delayed(Duration.zero); // let _restore finish
    return container.read(authControllerProvider.notifier);
  }

  Future<AuthController> setupShop() async {
    final auth = await start();
    await auth.completeSetup(
      shopId: 'shop1',
      phone: '+923001234567',
      shopName: 'Ali General Store',
      pin: '1234',
    );
    return auth;
  }

  test('a fresh phone needs first-time setup', () async {
    await start();
    expect(container.read(authControllerProvider), isA<AuthNeedsSetup>());
  });

  test('setup unlocks, stores only a PIN hash, and creates the shop',
      () async {
    await setupShop();
    expect(container.read(authControllerProvider), isA<AuthUnlocked>());
    expect(store.data[SecureKeys.pinHash], isNot(contains('1234')));
    expect((await db.shopDao.shopById('shop1'))?.name, 'Ali General Store');
  });

  test('after restart the app is locked and unlocks offline with phone + PIN',
      () async {
    await setupShop();
    container.dispose();

    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(store),
      pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10)),
      clockProvider.overrideWithValue(() => clock),
    ]);
    final auth = await start();
    expect(container.read(authControllerProvider), isA<AuthLocked>());

    expect(await auth.unlock(phoneInput: '0300 1234567', pin: '0000'), isFalse);
    expect(await auth.unlock(phoneInput: '0301 1234567', pin: '1234'), isFalse);
    expect(container.read(authControllerProvider), isA<AuthLocked>());

    expect(await auth.unlock(phoneInput: '0300 1234567', pin: '1234'), isTrue);
    expect(container.read(authControllerProvider), isA<AuthUnlocked>());
  });

  test('locks after 5 minutes in the background, not before', () async {
    final auth = await setupShop();

    auth.onBackgrounded();
    clock = clock.add(const Duration(minutes: 4));
    await auth.onForegrounded();
    expect(container.read(authControllerProvider), isA<AuthUnlocked>());

    auth.onBackgrounded();
    clock = clock.add(const Duration(minutes: 5));
    await auth.onForegrounded();
    expect(container.read(authControllerProvider), isA<AuthLocked>());
  });

  group('redirectForAuth', () {
    test('routes each auth state to the right screen', () {
      expect(redirectForAuth(const AuthLoading(), '/home'), '/splash');
      expect(redirectForAuth(const AuthNeedsSetup(), '/home'), '/setup');
      expect(redirectForAuth(const AuthNeedsSetup(), '/setup'), isNull);
      expect(redirectForAuth(const AuthLocked(phone: 'x'), '/bill'), '/login');
      expect(redirectForAuth(const AuthLocked(phone: 'x'), '/login'), isNull);
      expect(
        redirectForAuth(const AuthUnlocked(shopId: 's', phone: 'x'), '/login'),
        '/home',
      );
      expect(
        redirectForAuth(const AuthUnlocked(shopId: 's', phone: 'x'), '/saman'),
        isNull,
      );
    });
  });
}
