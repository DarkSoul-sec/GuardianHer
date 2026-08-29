import 'package:flutter/foundation.dart';

import 'vehicle_registration.dart';

/// Vehicle categories offered on the Safe Journey form (Phase D).
///
/// UI must render [label], never `name`.
enum VehicleType {
  auto,
  taxi,
  cab,
  bus,
  privateVehicle,
  other;

  String get label => switch (this) {
        VehicleType.auto => 'Auto',
        VehicleType.taxi => 'Taxi',
        VehicleType.cab => 'Cab',
        VehicleType.bus => 'Bus',
        VehicleType.privateVehicle => 'Private Vehicle',
        VehicleType.other => 'Other',
      };
}

/// The vehicle context of a Safe Journey (extended in Phase D).
///
/// PRIVACY: lives ONLY in memory for the duration of the journey/session —
/// never persisted, never logged ([toString] hides every value), never sent
/// anywhere by itself, never part of any URL or id. It may appear in a share
/// message ONLY when the user explicitly chooses to share the journey.
@immutable
class VehicleInfo {
  const VehicleInfo({
    required this.type,
    this.registrationNumber,
    this.driverName,
    this.bookingReference,
  });

  final VehicleType type;

  /// NORMALIZED registration ("DL01AB1234"). Null when the user chose not to
  /// enter one. Never put into ids, URLs, logs or analytics.
  final String? registrationNumber;

  final String? driverName;

  final String? bookingReference;

  bool get hasRegistration =>
      registrationNumber != null && registrationNumber!.isNotEmpty;

  /// Readable display form: spaced Indian format when possible
  /// ("DL 01 AB 1234"), otherwise the stored canonical text unchanged.
  String? get displayRegistrationNumber {
    final canonical = registrationNumber;
    if (canonical == null || canonical.isEmpty) return null;
    return formatRegistration(canonical);
  }

  @override
  String toString() =>
      'VehicleInfo(type: ${type.label}, '
      'registration: ${hasRegistration ? "provided" : "none"}, '
      'driver: ${driverName == null ? "none" : "provided"}, '
      'bookingRef: ${bookingReference == null ? "none" : "provided"})';

  @override
  bool operator ==(Object other) =>
      other is VehicleInfo &&
      other.type == type &&
      other.registrationNumber == registrationNumber &&
      other.driverName == driverName &&
      other.bookingReference == bookingReference;

  @override
  int get hashCode => Object.hash(
        type,
        registrationNumber,
        driverName,
        bookingReference,
      );
}
