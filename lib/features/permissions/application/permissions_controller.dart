import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../core/providers.dart';
import '../domain/permission_descriptor.dart';
import '../domain/permission_entry.dart';

/// Loads and updates the permission statuses shown in the Permissions Center.
class PermissionsController extends AsyncNotifier<List<PermissionEntry>> {
  PermissionService get _service => ref.read(permissionServiceProvider);

  @override
  Future<List<PermissionEntry>> build() async {
    final statuses = await Future.wait(
      permissionDescriptors.map((d) => _service.status(d.permission)),
    );
    return [
      for (var i = 0; i < permissionDescriptors.length; i++)
        PermissionEntry(
          descriptor: permissionDescriptors[i],
          status: statuses[i],
        ),
    ];
  }

  /// Requests [permission] through the permission service and refreshes the
  /// entry with the resulting status.
  Future<void> request(AppPermission permission) async {
    final status = await _service.request(permission);
    _replace(permission, status);
  }

  Future<void> openSettings() => _service.openSettings();

  void _replace(AppPermission permission, PermissionStatus status) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final entry in current)
        entry.descriptor.permission == permission
            ? entry.copyWith(status: status)
            : entry,
    ]);
  }
}