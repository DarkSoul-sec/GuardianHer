import 'dart:math';

import 'sos_status.dart';

/// A unique identifier for an [SosEvent].
///
/// Produced by [generate] using a cryptographically secure random source so
/// that ids cannot be guessed. The id is opaque: it carries no user data.
final class SosEventId {
  const SosEventId._(this.value);

  /// Creates an id from its canonical string form.
  ///
  /// Throws [ArgumentError] when [value] is not a valid id. Prefer [parse] for
  /// untrusted input.
  factory SosEventId(String value) {
    final id = SosEventId._(value);
    if (!id.isValid) {
      throw ArgumentError.value(value, 'value', 'Not a valid SosEventId');
    }
    return id;
  }

  /// Parses [value] and returns an id, or `null` when it is invalid.
  static SosEventId? tryParse(String value) {
    final id = SosEventId._(value);
    return id.isValid ? id : null;
  }

  /// Generates a fresh, cryptographically random id (32 lowercase hex chars).
  static SosEventId generate() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return SosEventId._(buffer.toString());
  }

  final String value;

  bool get isValid => value.length == 32 && RegExp(r'^[0-9a-f]+$').hasMatch(value);

  @override
  bool operator ==(Object other) => other is SosEventId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// An immutable, platform-independent record of one SOS session.
///
/// This is the single source of truth for a session's progress. The
/// [SosStateMachine] produces a new [SosEvent] for every transition; the
/// application layer never mutates a session in place.
class SosEvent {
  const SosEvent({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.countdownDuration,
    this.activatedAt,
    this.completedAt,
    this.reason,
  });

  final SosEventId id;

  /// Wall-clock time the session was started (injected, never `DateTime.now`).
  final DateTime startedAt;

  final SosStatus status;

  /// Length of the pre-activation countdown for this session.
  final Duration countdownDuration;

  /// Time the session entered the [SosStatus.active] state, if ever.
  final DateTime? activatedAt;

  /// Time the session entered the [SosStatus.completed] state, if ever.
  final DateTime? completedAt;

  /// Why the session ended; non-null only when [status] is completed.
  final SosTerminationReason? reason;

  /// Whether the session was cancelled by the user.
  bool get wasCancelled => reason == SosTerminationReason.cancelled;

  /// Whether the session ended normally.
  bool get wasCompleted => reason == SosTerminationReason.completed;

  SosEvent copyWith({
    SosStatus? status,
    DateTime? startedAt,
    Duration? countdownDuration,
    DateTime? activatedAt,
    DateTime? completedAt,
    SosTerminationReason? reason,
  }) {
    return SosEvent(
      id: id,
      startedAt: startedAt ?? this.startedAt,
      status: status ?? this.status,
      countdownDuration: countdownDuration ?? this.countdownDuration,
      activatedAt: activatedAt ?? this.activatedAt,
      completedAt: completedAt ?? this.completedAt,
      reason: reason ?? this.reason,
    );
  }
}
