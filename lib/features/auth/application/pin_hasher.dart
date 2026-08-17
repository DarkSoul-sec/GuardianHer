import 'package:pointycastle/export.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../domain/credential_policy.dart';
import '../domain/stored_pin_data.dart';

/// PIN format rules.
abstract final class PinPolicy {
  PinPolicy._();

  /// Exactly 6 digits for the initial release: short enough to type quickly,
  /// long enough to keep a 1e6 space infeasible to brute force given the
  /// PBKDF2 work factor and lockout schedule.
  static const int minLength = 6;
  static const int maxLength = 6;

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static bool isValid(String pin) {
    if (pin.length < minLength || pin.length > maxLength) return false;
    return _digitsOnly.hasMatch(pin);
  }
}

/// Derives and verifies PIN representations using PBKDF2-HMAC-SHA256.
///
/// Uses the standard pointycastle implementation; no custom cryptography.
/// Salts come from the operating system CSPRNG ([Random.secure]).
class PinHasher {
  const PinHasher({
    this.iterations = CredentialPolicy.defaultIterations,
    this.saltLength = 16,
    this.hashLength = 32,
  });

  /// PBKDF2-HMAC-SHA256 iteration count for newly created hashes. The actual
  /// count used for verification is read from the stored data.
  final int iterations;

  /// Random salt length in bytes (128-bit).
  final int saltLength;

  /// Derived key length in bytes (256-bit).
  final int hashLength;

  Uint8List generateSalt() {
    final random = Random.secure();
    final salt = Uint8List(saltLength);
    for (var i = 0; i < saltLength; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  Future<StoredPinData> hashPin(String pin) async {
    final salt = generateSalt();
    final hash = _derive(pin, salt, iterations);
    return StoredPinData(salt: salt, hash: hash, iterations: iterations);
  }

  Future<bool> verifyPin(String pin, StoredPinData stored) async {
    final hash = _derive(pin, stored.salt, stored.iterations);
    return _constantTimeEquals(hash, stored.hash);
  }

  Uint8List _derive(String pin, List<int> salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, hashLength));
    final output = Uint8List(hashLength);
    derivator.deriveKey(Uint8List.fromList(utf8.encode(pin)), 0, output, 0);
    return output;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}