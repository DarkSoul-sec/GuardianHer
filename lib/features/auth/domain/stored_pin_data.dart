import 'dart:convert';
import 'dart:typed_data';

import 'credential_policy.dart';

/// The securely derived representation of a PIN.
///
/// Only the salt, the PBKDF2-HMAC-SHA256 hash and the iteration count are
/// stored; the plaintext PIN is never persisted.
class StoredPinData {
  const StoredPinData({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  static const int version = 1;
  static const String algorithm = 'pbkdf2-hmac-sha256';

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;

  String encode() => jsonEncode({
        'v': version,
        'a': algorithm,
        'i': iterations,
        's': base64Encode(salt),
        'h': base64Encode(hash),
      });

  /// Decodes [encoded], returning `null` when the value is absent or invalid.
  ///
  /// Rejects credentials that do not satisfy [policy]: wrong format version or
  /// algorithm id, out-of-range iteration counts, or unexpected salt/hash
  /// lengths. Malformed values fail closed (the caller treats them as
  /// corrupted) so a tampered credential can never be used to authenticate.
  static StoredPinData? tryDecode(
    String encoded, {
    CredentialPolicy policy = const CredentialPolicy(),
  }) {
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      if (map['v'] != version || map['a'] != algorithm) return null;
      final iterations = map['i'] as int?;
      if (iterations == null) return null;
      final salt = base64Decode(map['s'] as String);
      final hash = base64Decode(map['h'] as String);
      if (!policy.isValid(
        iterations: iterations,
        saltLength: salt.length,
        hashLength: hash.length,
      )) {
        return null;
      }
      return StoredPinData(salt: salt, hash: hash, iterations: iterations);
    } on Object {
      return null;
    }
  }
}