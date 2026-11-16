import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted, iterated SHA-256 for the 4-digit app-lock PIN.
///
/// Honest scope: a 4-digit PIN has only 10,000 combinations, so this is a
/// local app lock, not strong security. The hash never leaves the phone and
/// lives in secure storage. Stored format: `v1$<iterations>$<salt>$<hash>`.
class PinHasher {
  const PinHasher({this.iterations = 10000});

  final int iterations;

  static final _random = Random.secure();

  String hash(String pin, {Uint8List? salt}) {
    final s = salt ?? _newSalt();
    final digest = _derive(pin, s, iterations);
    return 'v1\$$iterations\$${base64.encode(s)}\$${base64.encode(digest)}';
  }

  bool verify(String pin, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'v1') return false;
    final iters = int.tryParse(parts[1]);
    if (iters == null || iters <= 0) return false;
    try {
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual = _derive(pin, salt, iters);
      return _constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  static Uint8List _newSalt() =>
      Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256)));

  static Uint8List _derive(String pin, List<int> salt, int iterations) {
    final pinBytes = utf8.encode(pin);
    var h = sha256.convert([...salt, ...pinBytes]).bytes;
    for (var i = 0; i < iterations; i++) {
      h = sha256.convert([...h, ...salt, ...pinBytes]).bytes;
    }
    return Uint8List.fromList(h);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
