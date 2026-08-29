import '../../features/location/domain/location_point.dart';
import '../permissions/permission_service.dart';
import '../result/result.dart';

/// Abstraction over one-shot device location access.
///
/// Implementations are plugin-backed; presentation and application code never
/// touch Geolocator or Android location APIs directly. The interface exposes
/// only application/domain-friendly types — no platform-specific position or
/// permission classes leak across this boundary.
///
/// V1 is foreground, one-shot only: no continuous stream, no background
/// location, no foreground service.
abstract interface class LocationService {
  /// Whether the device's location services (GPS / network switch) are on.
  Future<bool> isLocationServiceEnabled();

  /// The current location permission state without prompting.
  Future<PermissionStatus> checkPermission();

  /// Requests foreground location permission and returns its resulting state.
  Future<PermissionStatus> requestPermission();

  /// Opens the device's location settings screen (where the GPS switch lives)
  /// so the user can enable location services. Returns once the user returns
  /// to the app.
  ///
  /// Note: a normal Android app cannot toggle GPS programmatically (that needs
  /// system privileges), so this is the supported way to reach the switch.
  Future<bool> openLocationSettings();

  /// Best-effort silent enable of location services (Android).
  ///
  /// Returns true when services are now on. A normal Android app can only do
  /// this if it holds `WRITE_SECURE_SETTINGS` (granted via adb) or is a device
  /// owner; otherwise this returns false and the caller should fall back to
  /// [openLocationSettings]. Never throws.
  Future<bool> enableLocationServices();

  /// Performs a single current-position request.
  ///
  /// Returns [LocationPoint] with the platform-reported accuracy, or a
  /// [LocationFailure]. Never starts a continuous stream and never keeps a
  /// subscription alive after returning.
  Future<Result<LocationPoint>> getCurrentLocation();
}
