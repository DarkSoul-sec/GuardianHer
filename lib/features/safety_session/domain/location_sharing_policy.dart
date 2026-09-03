import 'safety_session_type.dart';

/// Centralized location-sharing cadence policy (§5).
///
/// The single place that defines how often continuous-location safety
/// sessions request fixes. Features must read from here instead of
/// hardcoding intervals.
///
/// Battery behavior (§31):
/// * Intervals are deliberately coarse — a fix every 10–30 s is plenty for
///   "where are they right now" while keeping the GPS radio duty-cycled.
/// * Continuous capture only ever runs inside a visible foreground-service
///   session (SOS, journey). Nothing requests location without an
///   active session, and the requests stop the moment the session ends or
///   expires — enforced by the owning controllers' teardown paths.
final class LocationSharingPolicy {
  const LocationSharingPolicy();

  /// SOS emergency cadence: as fresh as it gets, battery be damned.
  Duration get sosInterval => const Duration(seconds: 10);

  /// Safe Journey cadence bounds and default. Requests outside the closed
  /// range are clamped so callers cannot silently create a tracking-heavy
  /// configuration.
  static const int journeyMinSeconds = 15;
  static const int journeyMaxSeconds = 30;
  static const int journeyDefaultSeconds = 20;

  Duration journeyInterval({int? requestedSeconds}) {
    final seconds = requestedSeconds ?? journeyDefaultSeconds;
    final clamped = seconds.clamp(journeyMinSeconds, journeyMaxSeconds);
    return Duration(seconds: clamped);
  }

  /// The interval a given session type should use.
  Duration intervalFor(SafetySessionType type) => switch (type) {
        SafetySessionType.sos => sosInterval,
        SafetySessionType.safeJourney => journeyInterval(),
      };
}