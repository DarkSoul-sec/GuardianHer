import 'package:permission_handler/permission_handler.dart' as ph;

import '../../core/permissions/permission_service.dart';
import 'permission_status_mapper.dart';

/// Centralized runtime permission handling backed by permission_handler.
///
/// Presentation code never calls this plugin directly; it goes through
/// [PermissionService].
class PermissionServiceImpl implements PermissionService {
  const PermissionServiceImpl();

  @override
  Future<PermissionStatus> status(AppPermission permission) async {
    final status = await mapAppPermission(permission).status;
    return mapPlatformPermissionStatus(status);
  }

  @override
  Future<PermissionStatus> request(AppPermission permission) async {
    final status = await mapAppPermission(permission).request();
    return mapPlatformPermissionStatus(status);
  }

  @override
  Future<void> openSettings() => ph.openAppSettings();
}