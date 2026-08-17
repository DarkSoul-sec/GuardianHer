/// The set of sensitive capabilities the app can request from the OS.
///
/// Permission request logic itself is not implemented in Phase 0; features
/// interact only through [PermissionService].
enum AppPermission {
  location,
  locationBackground,
  notifications,
  camera,
  microphone,
  phone,
  sms,
}

/// The resolved state of a requested [AppPermission].
enum PermissionStatus {
  /// Granted by the user.
  granted,

  /// Denied, but the user can be asked again.
  denied,

  /// Denied and must be changed in system Settings.
  permanentlyDenied,

  /// Restricted by the OS or policy (platform-specific).
  restricted,

  /// Partially granted (e.g. selected photos only).
  limited,
}

/// Centralized abstraction over OS runtime permissions.
///
/// Single source of truth for permission state, request flows and the
/// open-settings fallback. All features request permissions through this
/// service so behavior is consistent and testable; presentation code never
/// touches permission plugins directly.
abstract interface class PermissionService {
  /// Returns the current status of [permission].
  Future<PermissionStatus> status(AppPermission permission);

  /// Requests [permission] from the OS and returns its resulting status.
  Future<PermissionStatus> request(AppPermission permission);

  /// Opens the system settings screen for this app.
  Future<void> openSettings();
}