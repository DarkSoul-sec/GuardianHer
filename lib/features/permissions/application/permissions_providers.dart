import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/permission_entry.dart';
import 'permissions_controller.dart';

/// Loads all permission statuses for the Permissions Center.
final permissionsControllerProvider =
    AsyncNotifierProvider<PermissionsController, List<PermissionEntry>>(
  PermissionsController.new,
);