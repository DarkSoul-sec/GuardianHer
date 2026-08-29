import 'package:flutter/foundation.dart';

/// A single, immutable current-location fix.
///
/// Coordinates are in decimal degrees (WGS84). [capturedAt] is always UTC.
/// Values are trusted only after [isValid]: invalid coordinates are rejected by
/// the data layer instead of being silently accepted.
@immutable
class LocationPoint {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    this.isStale = false,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in meters as reported by the platform, or `0` when
  /// the platform could not quantify it. Raw value — never invented.
  final double accuracyMeters;

  /// UTC timestamp of the fix.
  final DateTime capturedAt;

  /// True when this fix comes from a cache older than the freshness window
  /// and is served only as an explicitly labeled fallback. A stale point must
  /// NEVER be presented to the user as a current fix.
  final bool isStale;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracyMeters >= 0;

  @override
  bool operator ==(Object other) =>
      other is LocationPoint &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMeters == accuracyMeters &&
      other.capturedAt == capturedAt &&
      other.isStale == isStale;

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, accuracyMeters, capturedAt, isStale);

  @override
  String toString() => 'LocationPoint(±${accuracyMeters}m'
      '${isStale ? ', stale' : ''})';
}
