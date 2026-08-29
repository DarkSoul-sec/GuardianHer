import 'safety_session_id.dart';
import 'safety_session_status.dart';
import 'safety_session_type.dart';

/// An active (or most recent) safety-related activity.
///
/// The session is the coordination record: *which* feature is running, since
/// when, for whom (trusted-contact ids only — never phone numbers), and in
/// which lifecycle state. It holds no coordinates and no location history;
/// location knowledge stays inside the owning feature.
class SafetySession {
  const SafetySession({
    required this.id,
    required this.type,
    required this.status,
    required this.startedAt,
    this.activatedAt,
    this.endedAt,
    this.recipientContactIds = const [],
  });

  /// A brand-new session in the [SafetySessionStatus.starting] state.
  factory SafetySession.start({
    required SafetySessionId id,
    required SafetySessionType type,
    required DateTime startedAt,
    List<String> recipientContactIds = const [],
  }) {
    return SafetySession(
      id: id,
      type: type,
      status: SafetySessionStatus.starting,
      startedAt: startedAt,
      recipientContactIds: List.unmodifiable(recipientContactIds),
    );
  }

  final SafetySessionId id;
  final SafetySessionType type;
  final SafetySessionStatus status;

  /// When the start request was accepted (UTC).
  final DateTime startedAt;

  /// When the session actually became [SafetySessionStatus.active], if it did.
  final DateTime? activatedAt;

  /// When the session reached a terminal state, if it did.
  final DateTime? endedAt;

  /// Trusted contacts that should receive updates about this session,
  /// referenced by their existing opaque contact ids (§23 — never copied
  /// phone numbers).
  final List<String> recipientContactIds;

  bool get isActiveLike => status.isActiveLike;
  bool get isTerminal => status.isTerminal;

  SafetySession copyWith({
    SafetySessionStatus? status,
    DateTime? activatedAt,
    DateTime? endedAt,
    List<String>? recipientContactIds,
  }) {
    return SafetySession(
      id: id,
      type: type,
      status: status ?? this.status,
      startedAt: startedAt,
      activatedAt: activatedAt ?? this.activatedAt,
      endedAt: endedAt ?? this.endedAt,
      recipientContactIds:
          recipientContactIds ?? this.recipientContactIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SafetySession &&
      other.id == id &&
      other.type == type &&
      other.status == status &&
      other.startedAt == startedAt &&
      other.activatedAt == activatedAt &&
      other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(id, type, status, startedAt, activatedAt);

  /// Privacy-aware: never includes recipients or any location-derived data.
  @override
  String toString() =>
      'SafetySession(${id.toString()}, ${type.storageName}, ${status.name})';
}
