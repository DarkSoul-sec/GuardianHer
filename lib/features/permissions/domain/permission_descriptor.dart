import 'package:flutter/material.dart';

import '../../../core/permissions/permission_service.dart';

/// Immutable description of a permission the app may eventually need.
class PermissionDescriptor {
  const PermissionDescriptor({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
    this.requestable = false,
  });

  final AppPermission permission;
  final String title;
  final String description;
  final IconData icon;

  /// Whether the current implemented features actually require this
  /// permission. Only these expose a request action.
  final bool requestable;
}

/// The curated permission catalog. Explanations describe why a permission may
/// be needed later; requests are only exposed when [PermissionDescriptor.requestable]
/// is true (none in Phase 1).
const List<PermissionDescriptor> permissionDescriptors = [
  PermissionDescriptor(
    permission: AppPermission.location,
    title: 'Location',
    description: 'Used to show your position and to include your location '
        'when you share an emergency alert.',
    icon: Icons.location_on_outlined,
  ),
  PermissionDescriptor(
    permission: AppPermission.locationBackground,
    title: 'Background location',
    description: 'May be needed to keep providing your location during an '
        'active emergency when the app is in the background. Not requested yet.',
    icon: Icons.location_searching_outlined,
  ),
  PermissionDescriptor(
    permission: AppPermission.notifications,
    title: 'Notifications',
    description: 'Used to keep you informed during an active emergency.',
    icon: Icons.notifications_outlined,
  ),
  PermissionDescriptor(
    permission: AppPermission.camera,
    title: 'Camera',
    description: 'May be used to capture visual evidence in a future safety '
        'feature. Not currently used.',
    icon: Icons.photo_camera_outlined,
  ),
  PermissionDescriptor(
    permission: AppPermission.microphone,
    title: 'Microphone',
    description: 'May be used for ambient awareness in a future safety '
        'feature. Not currently used.',
    icon: Icons.mic_outlined,
  ),
  PermissionDescriptor(
    permission: AppPermission.phone,
    title: 'Phone calls',
    description: 'GuardianHer opens the system dialer for emergency calls and '
        'does not request the ability to place calls itself.',
    icon: Icons.call_outlined,
  ),
  PermissionDescriptor(
    permission: AppPermission.sms,
    title: 'Messages (SMS)',
    description: 'GuardianHer composes emergency messages through your '
        'messaging app and does not request the ability to send SMS directly.',
    icon: Icons.sms_outlined,
  ),
];