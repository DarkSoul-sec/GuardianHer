import '../../../core/error/failures.dart';

/// Base type for current-location failures.
sealed class LocationFailure extends Failure {
  const LocationFailure({
    super.message = 'A location error occurred.',
    super.code,
  });
}

/// The device location services (GPS / network switch) are turned off.
final class LocationServicesDisabledFailure extends LocationFailure {
  const LocationServicesDisabledFailure({
    super.message = 'Location services are turned off.',
    super.code = 'location_services_disabled',
  });
}

/// The app is not configured for location access (permission declarations
/// missing from the manifest).
final class LocationPermissionMissingFailure extends LocationFailure {
  const LocationPermissionMissingFailure({
    super.message = 'Location access is not configured on this device.',
    super.code = 'location_permission_missing',
  });
}

/// The platform reported coordinates that violate the domain constraints.
final class InvalidLocationCoordinatesFailure extends LocationFailure {
  const InvalidLocationCoordinatesFailure({
    super.message = 'The device reported an invalid location.',
    super.code = 'invalid_location_coordinates',
  });
}

/// The location request exceeded its time limit.
final class LocationTimeoutFailure extends LocationFailure {
  const LocationTimeoutFailure({
    super.message = 'The location could not be determined. Please try again.',
    super.code = 'location_timeout',
  });
}

/// The location could not be determined for another reason (no fix, platform
/// exception, etc.).
final class LocationUnavailableFailure extends LocationFailure {
  const LocationUnavailableFailure({
    super.message = 'Location unavailable.',
    super.code = 'location_unavailable',
  });
}
