import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'permissions/permission_service.dart';
import 'platform/call_service.dart';
import 'platform/location_service.dart';
import 'platform/map_service.dart';
import 'platform/notification_service.dart';
import 'platform/sms_service.dart';
import 'security/secure_storage_service.dart';

/// Dependency injection wiring for core platform services.
///
/// Concrete, plugin-backed implementations are provided in later phases.
/// Until then these providers throw [UnimplementedError] when read, which
/// keeps the dependency graph explicit and forces feature code to receive an
/// injected implementation (or a test fake) instead of touching plugins
/// directly. Tests override these providers with fakes.
final locationServiceProvider = Provider<LocationService>(
  (ref) => throw UnimplementedError('LocationService is provided in a later phase.'),
);

final callServiceProvider = Provider<CallService>(
  (ref) => throw UnimplementedError('CallService is provided in a later phase.'),
);

final smsServiceProvider = Provider<SmsService>(
  (ref) => throw UnimplementedError('SmsService is provided in a later phase.'),
);

final mapServiceProvider = Provider<MapService>(
  (ref) => throw UnimplementedError('MapService is provided in a later phase.'),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('NotificationService is provided in a later phase.'),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => throw UnimplementedError('PermissionService is provided in a later phase.'),
);

final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => throw UnimplementedError('SecureStorageService is provided in a later phase.'),
);