import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_info_service_impl.dart';
import '../data/biometric_service_impl.dart';
import '../data/data_cleanup_service_impl.dart';
import '../data/permission_service_impl.dart';
import '../data/preferences_service_impl.dart';
import '../data/secure_storage_service_impl.dart';
import 'permissions/permission_service.dart';
import 'platform/app_info_service.dart';
import 'platform/biometric_service.dart';
import 'platform/call_service.dart';
import 'platform/location_service.dart';
import 'platform/map_service.dart';
import 'platform/notification_service.dart';
import 'platform/preferences_service.dart';
import 'platform/sms_service.dart';
import 'security/data_cleanup_service.dart';
import 'security/secure_storage_service.dart';

/// Dependency injection wiring for core platform services.
///
/// This file is the composition root: abstract service interfaces are bound to
/// their data-layer implementations here. Tests override these providers with
/// fakes so no plugin platform channel is touched.
final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => const FlutterSecureStorageService(),
);

final preferencesServiceProvider = Provider<PreferencesService>(
  (ref) => const SharedPreferencesService(),
);

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => LocalAuthBiometricService(),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionServiceImpl(),
);

final appInfoServiceProvider = Provider<AppInfoService>(
  (ref) => const PackageInfoAppInfoService(),
);

/// App identity (name, version, build number).
final appInfoProvider = FutureProvider<AppInfo>(
  (ref) => ref.watch(appInfoServiceProvider).getAppInfo(),
);

final dataCleanupServiceProvider = Provider<DataCleanupService>(
  (ref) => DataCleanupServiceImpl(
    secureStorage: ref.watch(secureStorageServiceProvider),
    preferences: ref.watch(preferencesServiceProvider),
  ),
);

/// Services below are not required by any Phase 1 feature. They throw if read
/// so an implementation must be explicitly provided before a feature uses them.
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