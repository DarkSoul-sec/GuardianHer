import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/auth/domain/credential_policy.dart';
import 'package:guardianher/features/auth/domain/stored_pin_data.dart';

/// Encodes a raw credential payload, bypassing the writer so tests can craft
/// credentials that violate the policy.
String encodePin({
  int version = 1,
  String algorithm = 'pbkdf2-hmac-sha256',
  required int iterations,
  required List<int> salt,
  required List<int> hash,
}) {
  return jsonEncode({
    'v': version,
    'a': algorithm,
    'i': iterations,
    's': base64Encode(salt),
    'h': base64Encode(hash),
  });
}

void main() {
  const policy = CredentialPolicy();

  List<int> saltOfLength(int length) => List<int>.filled(length, 7);
  List<int> hashOfLength(int length) => List<int>.filled(length, 9);

  group('CredentialPolicy', () {
    test('accepts the production defaults', () {
      expect(
        policy.isValid(iterations: 600000, saltLength: 16, hashLength: 32),
        isTrue,
      );
    });

    test('rejects iteration counts below the minimum', () {
      expect(
        policy.isValid(
          iterations: policy.minIterations - 1,
          saltLength: 16,
          hashLength: 32,
        ),
        isFalse,
      );
    });

    test('rejects iteration counts above the maximum', () {
      expect(
        policy.isValid(
          iterations: policy.maxIterations + 1,
          saltLength: 16,
          hashLength: 32,
        ),
        isFalse,
      );
    });

    test('rejects unexpected salt lengths', () {
      expect(
        policy.isValid(iterations: 600000, saltLength: 8, hashLength: 32),
        isFalse,
      );
    });

    test('rejects unexpected hash lengths', () {
      expect(
        policy.isValid(iterations: 600000, saltLength: 16, hashLength: 16),
        isFalse,
      );
    });
  });

  group('StoredPinData.tryDecode policy enforcement', () {
    test('decodes a credential that satisfies the policy', () {
      final encoded = encodePin(
        iterations: 600000,
        salt: saltOfLength(16),
        hash: hashOfLength(32),
      );

      final decoded = StoredPinData.tryDecode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.iterations, 600000);
      expect(decoded.salt.length, 16);
      expect(decoded.hash.length, 32);
    });

    test('rejects an unknown format version', () {
      final encoded = encodePin(
        version: 2,
        iterations: 600000,
        salt: saltOfLength(16),
        hash: hashOfLength(32),
      );

      expect(StoredPinData.tryDecode(encoded), isNull);
    });

    test('rejects an unknown algorithm', () {
      final encoded = encodePin(
        algorithm: 'md5',
        iterations: 600000,
        salt: saltOfLength(16),
        hash: hashOfLength(32),
      );

      expect(StoredPinData.tryDecode(encoded), isNull);
    });

    test('rejects iteration counts below the minimum', () {
      final encoded = encodePin(
        iterations: 1000,
        salt: saltOfLength(16),
        hash: hashOfLength(32),
      );

      expect(StoredPinData.tryDecode(encoded), isNull);
    });

    test('rejects excessive iteration counts', () {
      final encoded = encodePin(
        iterations: 20000000,
        salt: saltOfLength(16),
        hash: hashOfLength(32),
      );

      expect(StoredPinData.tryDecode(encoded), isNull);
    });

    test('rejects invalid salt lengths', () {
      final encoded = encodePin(
        iterations: 600000,
        salt: saltOfLength(8),
        hash: hashOfLength(32),
      );

      expect(StoredPinData.tryDecode(encoded), isNull);
    });

    test('rejects invalid hash lengths', () {
      final encoded = encodePin(
        iterations: 600000,
        salt: saltOfLength(16),
        hash: hashOfLength(16),
      );

      expect(StoredPinData.tryDecode(encoded), isNull);
    });

    test('returns null for malformed data', () {
      expect(StoredPinData.tryDecode('not-json'), isNull);
      expect(StoredPinData.tryDecode('{"i": 600000}'), isNull);
      expect(
        StoredPinData.tryDecode(
          encodePin(
            iterations: 600000,
            salt: saltOfLength(16),
            hash: hashOfLength(32),
          ).replaceAll('"s":', '"bad":'),
        ),
        isNull,
      );
    });
  });
}