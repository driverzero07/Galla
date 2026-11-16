import 'package:flutter_test/flutter_test.dart';
import 'package:galla/features/auth/domain/pin_hasher.dart';

void main() {
  const hasher = PinHasher(iterations: 50); // fast for tests

  test('correct PIN verifies, wrong PIN does not', () {
    final stored = hasher.hash('1234');
    expect(hasher.verify('1234', stored), isTrue);
    expect(hasher.verify('1235', stored), isFalse);
    expect(hasher.verify('', stored), isFalse);
  });

  test('the PIN is never stored in plain text', () {
    final stored = hasher.hash('4821');
    expect(stored.contains('4821'), isFalse);
    expect(stored.startsWith(r'v1$'), isTrue);
  });

  test('same PIN hashes differently each time (random salt)', () {
    expect(hasher.hash('1234'), isNot(hasher.hash('1234')));
  });

  test('garbage stored values fail safely', () {
    expect(hasher.verify('1234', ''), isFalse);
    expect(hasher.verify('1234', 'nonsense'), isFalse);
    expect(hasher.verify('1234', r'v1$x$y$z'), isFalse);
  });

  test('verify uses the iteration count stored in the hash', () {
    final stored = const PinHasher(iterations: 7).hash('9999');
    expect(const PinHasher(iterations: 100).verify('9999', stored), isTrue);
  });
}
