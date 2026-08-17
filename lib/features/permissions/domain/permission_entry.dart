import '../../../core/permissions/permission_service.dart';
import 'permission_descriptor.dart';

/// A permission descriptor paired with its current OS status.
class PermissionEntry {
  const PermissionEntry({required this.descriptor, required this.status});

  final PermissionDescriptor descriptor;
  final PermissionStatus status;

  bool get requestable => descriptor.requestable;
  bool get permanentlyDenied => status == PermissionStatus.permanentlyDenied;

  PermissionEntry copyWith({PermissionStatus? status}) {
    return PermissionEntry(
      descriptor: descriptor,
      status: status ?? this.status,
    );
  }
}