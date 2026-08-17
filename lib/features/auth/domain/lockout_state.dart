import 'dart:convert';

/// Failed-attempt accounting that survives app restarts.
class LockoutState {
  const LockoutState({required this.failedAttempts, this.lockoutUntil});

  const LockoutState.initial() : this(failedAttempts: 0);

  final int failedAttempts;

  /// Absolute time until which the app is locked out, or `null` when the user
  /// may attempt again immediately.
  final DateTime? lockoutUntil;

  bool get isLockedOut =>
      lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now());

  String encode() => jsonEncode({
        'a': failedAttempts,
        'u': lockoutUntil?.millisecondsSinceEpoch,
      });

  static LockoutState? tryDecode(String encoded) {
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      final attempts = map['a'] as int?;
      if (attempts == null || attempts < 0) return null;
      final untilMs = map['u'] as int?;
      return LockoutState(
        failedAttempts: attempts,
        lockoutUntil: untilMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(untilMs),
      );
    } on Object {
      return null;
    }
  }
}