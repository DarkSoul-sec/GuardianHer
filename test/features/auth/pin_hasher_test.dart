import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/auth/application/pin_hasher.dart';
import 'package:guardianher/features/auth/domain/credential_policy.dart';

void main() {
  group('PinPolicy', () {
    test('accepts exactly 6 digits', () {
      expect(PinPolicy.isValid('123456'), isTrue);
    });

    test('rejects fewer than 6 digits', () {
      expect(PinPolicy.isValid('12345'), isFalse);
      expect(PinPolicy.isValid('123'), isFalse);
    });

    test('rejects more than 6 digits', () {
      expect(PinPolicy.isValid('1234567'), isFalse);
    });

    test('rejects non-digit characters', () {
      expect(PinPolicy.isValid('12345a'), isFalse);
      expect(PinPolicy.isValid('123 45'), isFalse);
    });
  });

  group('PinHasher', () {
    test('default iterations match the production credential policy', () {
      expect(const PinHasher().iterations, CredentialPolicy().minIterations);
    });

    test('the stored representation contains no plaintext PIN', () async {
      const hasher = PinHasher(iterations: 1000);
      final stored = await hasher.hashPin('123456');

      final encoded = stored.encode();
      expect(encoded.contains('123456'), isFalse);
      expect(utf8.decode(stored.salt, allowMalformed: true), isNot('123456'));
      expect(utf8.decode(stored.hash, allowMalformed: true), isNot('123456'));
    });

    test('uses a fresh random salt for every hash', () async {
      const hasher = PinHasher(iterations: 1000);
      final first = await hasher.hashPin('123456');
      final second = await hasher.hashPin('123456');

      expect(first.salt, isNot(equals(second.salt)));
      expect(first.hash, isNot(equals(second.hash)));
    });

    test('salt and hash have the expected lengths', () async {
      const hasher = PinHasher(iterations: 1000);
      final stored = await hasher.hashPin('123456');

      expect(stored.salt.length, 16);
      expect(stored.hash.length, 32);
    });

    test('verification honors the stored iteration count', () async {
      const writer = PinHasher(iterations: 1000);
      final stored = await writer.hashPin('123456');
      expect(stored.iterations, 1000);

      // A verifier with a different default must still use the stored count.
      const verifier = PinHasher(iterations: 2000);
      expect(await verifier.verifyPin('123456', stored), isTrue);
      expect(await verifier.verifyPin('000000', stored), isFalse);
    });
  });
}