import 'dart:math';

/// A unique, opaque identifier for a safety session.
///
/// 32 lowercase hex chars (128 bits of secure randomness) so ids are neither
/// guessable nor enumerable. The id carries no user data: no phone numbers,
/// no coordinates, no contact names.
final class SafetySessionId {
  const SafetySessionId._(this.value);

  /// Creates an id from its canonical string form.
  ///
  /// Throws [ArgumentError] when [value] is not valid; prefer [tryParse] for
  /// untrusted input.
  factory SafetySessionId(String value) {
    final id = SafetySessionId._(value);
    if (!id.isValid) {
      throw ArgumentError.value(value, 'value', 'Not a valid SafetySessionId');
    }
    return id;
  }

  /// Parses [value], returning `null` when it is not a valid id.
  static SafetySessionId? tryParse(String value) {
    final id = SafetySessionId._(value);
    return id.isValid ? id : null;
  }

  /// Generates a fresh, cryptographically random id.
  static SafetySessionId generate() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return SafetySessionId._(buffer.toString());
  }

  final String value;

  bool get isValid =>
      value.length == 32 && RegExp(r'^[0-9a-f]+$').hasMatch(value);

  @override
  bool operator ==(Object other) =>
      other is SafetySessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SafetySessionId(${value.substring(0, 8)}…)';
}
