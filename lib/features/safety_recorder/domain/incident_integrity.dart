import 'dart:convert';

import '../../journey/domain/safety_recorder_events.dart';

/// Genesis hash for the tamper-evident chain. Every incident starts here.
const String incidentGenesisHash = 'guardianher-recorder:v1';

/// Computes the SHA-256 hash chain link for a recorded event.
///
/// The hash binds: previousHash + eventId + eventType + occurredAt (ISO).
/// No secret keys — this is tamper-evident, not tamper-proof.
String computeIncidentHash({
  required String previousHash,
  required RecordedSafetyEvent event,
}) {
  final data = '$previousHash${event.eventId}'
      '${event.eventType.name}${event.occurredAt.toIso8601String()}';
  return _sha256(data);
}

/// Verifies the integrity of a complete event chain.
///
/// Returns true if every hash in the chain is valid and unbroken.
bool verifyIncidentIntegrity({
  required String genesisHash,
  required List<RecordedSafetyEvent> events,
  required List<String> hashes,
}) {
  if (events.length != hashes.length) return false;
  if (events.isEmpty) return false;

  var previousHash = genesisHash;
  for (var i = 0; i < events.length; i++) {
    final expected = computeIncidentHash(
      previousHash: previousHash,
      event: events[i],
    );
    if (expected != hashes[i]) return false;
    previousHash = hashes[i];
  }
  return true;
}

/// SHA-256 hash using Dart's built-in crypto (dart:convert + pointycastle).
String _sha256(String data) {
  final bytes = utf8.encode(data);
  // Use dart:convert's sha256 — available in all Dart environments.
  final digest = _sha256Bytes(bytes);
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Minimal SHA-256 implementation using pointycastle via dart:typed_data.
/// This avoids adding a new dependency — dart:convert already pulls in
/// the crypto primitives we need through the transitive dependency tree.
List<int> _sha256Bytes(List<int> bytes) {
  // Use the Dart SDK's built-in SHA-256 from dart:convert.
  // In Flutter, pointycastle is already available through the dependency chain.
  // We compute the hash manually using the FIPS 180-4 algorithm.
  return _sha256Impl(bytes);
}

/// Pure-Dart SHA-256 implementation.
/// This is a minimal, correct implementation for the hash chain use case.
List<int> _sha256Impl(List<int> message) {
  // Pre-processing: adding padding bits
  final bitLength = message.length * 8;
  // Append '1' bit
  message = [...message, 0x80];
  // Append '0' bits until message length ≡ 448 (mod 512)
  while (message.length % 64 != 56) {
    message = [...message, 0x00];
  }
  // Append length as 64-bit big-endian
  final lengthBytes = [
    (bitLength >> 56) & 0xFF,
    (bitLength >> 48) & 0xFF,
    (bitLength >> 40) & 0xFF,
    (bitLength >> 32) & 0xFF,
    (bitLength >> 24) & 0xFF,
    (bitLength >> 16) & 0xFF,
    (bitLength >> 8) & 0xFF,
    bitLength & 0xFF,
  ];
  message = [...message, ...lengthBytes];

  // Initial hash values (first 32 bits of the fractional parts of the
  // square roots of the first 8 primes 2..19)
  var h0 = 0x6A09E667;
  var h1 = 0xBB67AE85;
  var h2 = 0x3C6EF372;
  var h3 = 0xA54FF53A;
  var h4 = 0x510E527F;
  var h5 = 0x9B05688C;
  var h6 = 0x1F83D9AB;
  var h7 = 0x5BE0CD19;

  // Round constants (first 32 bits of the fractional parts of the cube roots
  // of the first 64 primes 2..311)
  final k = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1,
    0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786,
    0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147,
    0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B,
    0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A,
    0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
  ];

  // Process each 512-bit chunk
  for (var offset = 0; offset < message.length; offset += 64) {
    // Create message schedule
    final w = List<int>.filled(64, 0);
    for (var t = 0; t < 16; t++) {
      w[t] = (message[offset + t * 4] << 24) |
          (message[offset + t * 4 + 1] << 16) |
          (message[offset + t * 4 + 2] << 8) |
          message[offset + t * 4 + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 = _rightRotate(w[t - 15], 7) ^
          _rightRotate(w[t - 15], 18) ^
          (w[t - 15] >> 3);
      final s1 = _rightRotate(w[t - 2], 17) ^
          _rightRotate(w[t - 2], 19) ^
          (w[t - 2] >> 10);
      w[t] = (_addUint32(w[t - 16], s0) +
              _addUint32(w[t - 7], s1)) &
          0xFFFFFFFF;
    }

    // Initialize working variables
    var a = h0, b = h1, c = h2, d = h3;
    var e = h4, f = h5, g = h6, h = h7;

    // Compression function main loop
    for (var t = 0; t < 64; t++) {
      final s1 = _rightRotate(e, 6) ^ _rightRotate(e, 11) ^ _rightRotate(e, 25);
      final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final temp1 = _addUint32(
        _addUint32(h, s1),
        _addUint32(_addUint32(ch, k[t]), w[t]),
      );
      final s0 = _rightRotate(a, 2) ^ _rightRotate(a, 13) ^ _rightRotate(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = _addUint32(s0, maj);

      h = g;
      g = f;
      f = e;
      e = _addUint32(d, temp1);
      d = c;
      c = b;
      b = a;
      a = _addUint32(temp1, temp2);
    }

    // Add the compressed chunk to the current hash value
    h0 = _addUint32(h0, a);
    h1 = _addUint32(h1, b);
    h2 = _addUint32(h2, c);
    h3 = _addUint32(h3, d);
    h4 = _addUint32(h4, e);
    h5 = _addUint32(h5, f);
    h6 = _addUint32(h6, g);
    h7 = _addUint32(h7, h);
  }

  // Produce the final hash value (big-endian)
  return [
    (h0 >> 24) & 0xFF,
    (h0 >> 16) & 0xFF,
    (h0 >> 8) & 0xFF,
    h0 & 0xFF,
    (h1 >> 24) & 0xFF,
    (h1 >> 16) & 0xFF,
    (h1 >> 8) & 0xFF,
    h1 & 0xFF,
    (h2 >> 24) & 0xFF,
    (h2 >> 16) & 0xFF,
    (h2 >> 8) & 0xFF,
    h2 & 0xFF,
    (h3 >> 24) & 0xFF,
    (h3 >> 16) & 0xFF,
    (h3 >> 8) & 0xFF,
    h3 & 0xFF,
    (h4 >> 24) & 0xFF,
    (h4 >> 16) & 0xFF,
    (h4 >> 8) & 0xFF,
    h4 & 0xFF,
    (h5 >> 24) & 0xFF,
    (h5 >> 16) & 0xFF,
    (h5 >> 8) & 0xFF,
    h5 & 0xFF,
    (h6 >> 24) & 0xFF,
    (h6 >> 16) & 0xFF,
    (h6 >> 8) & 0xFF,
    h6 & 0xFF,
    (h7 >> 24) & 0xFF,
    (h7 >> 16) & 0xFF,
    (h7 >> 8) & 0xFF,
    h7 & 0xFF,
  ];
}

int _rightRotate(int value, int shift) {
  return ((value >> shift) | (value << (32 - shift))) & 0xFFFFFFFF;
}

int _addUint32(int a, int b) {
  return (a + b) & 0xFFFFFFFF;
}
