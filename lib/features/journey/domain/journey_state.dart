import '../../safety_session/domain/safety_session.dart';
import 'vehicle_info.dart';

export 'vehicle_info.dart';

/// Why a journey ended. The journey never ends silently: the reason is shown.
enum JourneyEndReason {
  /// The user pressed "End Journey" (arrived safely).
  arrived,

  /// A shake SOS armed while travelling: the journey handed over to the
  /// authoritative SOS pipeline and closed itself — never two trackers.
  escalatedToSos,
}

/// Lifecycle of a Safe Journey (Phase C).
///
/// Mirrors the SOS phase shapes: sealed states the UI switches over. The
/// ledger underneath is a [SafetySession] (type `safeJourney`) driven by the
/// shared [SafetySessionMachine]; live TRACKING is delegated to the existing
/// LiveLocation machinery (one tracker at a time, always).
sealed class JourneyState {
  const JourneyState();

  /// Whether a journey currently occupies the feature (start refused while
  /// true, except by this state machine itself).
  bool get isActiveLike => this is JourneyStarting || this is JourneyActive;
}

/// No journey. Entry point for a new one.
final class JourneyIdle extends JourneyState {
  const JourneyIdle({this.notice});

  /// Honest one-line explanation when a start attempt was refused (e.g. an
  /// emergency is active). Null right after boot.
  final String? notice;

  @override
  bool operator ==(Object other) =>
      other is JourneyIdle && other.notice == notice;

  @override
  int get hashCode => notice.hashCode;
}

/// Start requested: permission/service/backend pre-flight is running.
final class JourneyStarting extends JourneyState {
  const JourneyStarting({required this.session, this.vehicle});

  final SafetySession session;

  final VehicleInfo? vehicle;

  @override
  bool get isActiveLike => true;
}

/// Tracking and sharing are live.
final class JourneyActive extends JourneyState {
  const JourneyActive({
    required this.session,
    required this.shareUrl,
    required this.expiresAt,
    this.vehicle,
    this.shareExpired = false,
  });

  final SafetySession session;

  final VehicleInfo? vehicle;

  /// The ONE shareable link. Empty while backend creation is still retrying
  /// offline — the UI must say "waiting", never fake a link.
  final String shareUrl;

  final DateTime expiresAt;

  /// The share link TTL elapsed (server cap): the journey itself continues,
  /// but there is nothing left to share until the user shares again.
  final bool shareExpired;

  JourneyActive copyWith({
    String? shareUrl,
    DateTime? expiresAt,
    bool? shareExpired,
  }) =>
      JourneyActive(
        session: session,
        vehicle: vehicle,
        shareUrl: shareUrl ?? this.shareUrl,
        expiresAt: expiresAt ?? this.expiresAt,
        shareExpired: shareExpired ?? this.shareExpired,
      );

  @override
  bool get isActiveLike => true;

  @override
  bool operator ==(Object other) =>
      other is JourneyActive &&
      other.session == session &&
      other.shareUrl == shareUrl &&
      other.expiresAt == expiresAt &&
      other.shareExpired == shareExpired;

  @override
  int get hashCode => Object.hash(session, shareUrl, expiresAt, shareExpired);

  @override
  String toString() => 'JourneyActive(${session.id}, never coordinates)';
}

/// Terminal. [reason] explains what happened; UI shows it verbatim-ish.
///
/// The vehicle and start time ride along ONLY for the completion summary —
/// they die with this state (dismissCompletion drops them; nothing is
/// persisted), so vehicle context never outlives the session.
final class JourneyCompleted extends JourneyState {
  const JourneyCompleted({
    required this.reason,
    required this.endedAt,
    required this.startedAt,
    this.vehicle,
  });

  final JourneyEndReason reason;

  final DateTime endedAt;

  final DateTime startedAt;

  final VehicleInfo? vehicle;

  @override
  bool operator ==(Object other) =>
      other is JourneyCompleted &&
      other.reason == reason &&
      other.endedAt == endedAt &&
      other.startedAt == startedAt &&
      other.vehicle == vehicle;

  @override
  int get hashCode => Object.hash(reason, endedAt, startedAt, vehicle);
}
