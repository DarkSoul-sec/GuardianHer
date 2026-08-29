import 'package:flutter/foundation.dart';

import '../domain/location_format.dart';
import '../domain/location_point.dart';

/// High-level status of the one-shot current-location flow.
enum LocationStatus {
  /// No capture has been attempted yet.
  idle,

  /// A capture request is in flight.
  loading,

  /// A valid fix was obtained.
  captured,

  /// The fix failed (no fix, platform error).
  unavailable,

  /// Every live location attempt timed out and no usable cache existed.
  timeout,

  /// The user denied location permission.
  denied,

  /// The device location services are switched off.
  servicesDisabled,
}

/// Immutable view of the current-location flow shown to the UI.
@immutable
final class LocationState {
  const LocationState({
    this.status = LocationStatus.idle,
    this.point,
    this.message,
    this.canRetry = false,
    this.openSettings = false,
    this.openLocationSettings = false,
  });

  final LocationStatus status;

  /// The captured fix when [status] is [LocationStatus.captured].
  final LocationPoint? point;

  /// A short, honest user-facing explanation when location is unavailable.
  final String? message;

  /// Whether the user can simply try again from the current screen.
  final bool canRetry;

  /// Whether the appropriate recovery is opening the app's settings page
  /// (e.g. a permanently denied permission).
  final bool openSettings;

  /// Whether the appropriate recovery is opening the device's location
  /// settings (the GPS switch). Android apps cannot toggle GPS themselves, so
  /// we take the user straight to the switch and auto-retry on return.
  final bool openLocationSettings;

  /// Short status line for compact contexts (e.g. the SOS active screen).
  ///
  /// The wording is honest per state: a timeout is never reported as a
  /// generic "unavailable", and a denied permission is distinguished from
  /// switched-off services.
  String? get statusLabel {
    final point = this.point;
    return switch (status) {
      LocationStatus.idle => null,
      LocationStatus.loading => 'Getting your location…',
      // A cached fallback is never presented as a current capture.
      LocationStatus.captured when point != null && point.isStale =>
        'Last known location',
      LocationStatus.captured => 'Location captured',
      LocationStatus.timeout => "Couldn't get your current location",
      LocationStatus.unavailable => 'Location unavailable',
      LocationStatus.denied => 'Location permission unavailable',
      LocationStatus.servicesDisabled => 'Location is turned off',
    };
  }

  /// Optional second line for compact contexts, giving the detail that makes
  /// the primary label actionable (accuracy for a capture, age for a stale
  /// fallback, the consequence of services being off). Null while idle.
  String? get statusDetail {
    final point = this.point;
    return switch (status) {
      LocationStatus.idle => null,
      LocationStatus.loading =>
        'Please keep GuardianHer open if possible.',
      LocationStatus.captured when point != null && point.isStale =>
        formatCapturedAge(point.capturedAt),
      LocationStatus.captured when point != null =>
        'Accuracy: ±${formatAccuracy(point.accuracyMeters)}',
      LocationStatus.captured => null,
      LocationStatus.timeout => null,
      LocationStatus.unavailable => null,
      LocationStatus.denied => null,
      LocationStatus.servicesDisabled =>
        'Your SOS is active, but your location could not be obtained.',
    };
  }

  LocationState copyWith({
    LocationStatus? status,
    LocationPoint? Function()? point,
    String? Function()? message,
    bool? canRetry,
    bool? openSettings,
    bool? openLocationSettings,
  }) {
    return LocationState(
      status: status ?? this.status,
      point: point != null ? point() : this.point,
      message: message != null ? message() : this.message,
      canRetry: canRetry ?? this.canRetry,
      openSettings: openSettings ?? this.openSettings,
      openLocationSettings: openLocationSettings ?? this.openLocationSettings,
    );
  }
}