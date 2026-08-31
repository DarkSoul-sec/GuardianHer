import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/onboarding/data/datasources/device_admin_datasource.dart';
import 'permission_onboarding_notifier.dart';

final deviceAdminDataSourceProvider = Provider<DeviceAdminDataSource>(
  (ref) => DeviceAdminDataSource(),
);

final permissionOnboardingNotifierProvider =
    StateNotifierProvider<PermissionOnboardingNotifier, PermissionOnboardingState>(
  (ref) => PermissionOnboardingNotifier(
    deviceAdminDataSource: ref.watch(deviceAdminDataSourceProvider),
    directSmsService: ref.watch(directSmsServiceProvider),
    shakeSosService: ref.watch(shakeSosServiceProvider),
    ref: ref,
  ),
);