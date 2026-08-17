import 'package:permission_handler/permission_handler.dart' as ph;

import '../../core/permissions/permission_service.dart';

/// Maps [AppPermission] to the platform permission.
ph.Permission mapAppPermission(AppPermission permission) {
  return switch (permission) {
    AppPermission.location => ph.Permission.location,
    AppPermission.locationBackground => ph.Permission.locationAlways,
    AppPermission.notifications => ph.Permission.notification,
    AppPermission.camera => ph.Permission.camera,
    AppPermission.microphone => ph.Permission.microphone,
    AppPermission.phone => ph.Permission.phone,
    AppPermission.sms => ph.Permission.sms,
  };
}

/// Maps the platform permission status to our domain status.
PermissionStatus mapPlatformPermissionStatus(ph.PermissionStatus status) {
  return switch (status) {
    ph.PermissionStatus.granted => PermissionStatus.granted,
    ph.PermissionStatus.denied => PermissionStatus.denied,
    ph.PermissionStatus.restricted => PermissionStatus.restricted,
    ph.PermissionStatus.limited => PermissionStatus.limited,
    ph.PermissionStatus.permanentlyDenied => PermissionStatus.permanentlyDenied,
    // iOS-only provisional grant is treated as not-yet-granted.
    ph.PermissionStatus.provisional => PermissionStatus.denied,
  };
}