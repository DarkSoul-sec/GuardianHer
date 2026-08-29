import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';

import '../data/datasources/device_admin_datasource.dart';
import 'permission_onboarding_notifier.dart';

final deviceAdminDataSourceProvider = Provider<DeviceAdminDataSource>(
  (ref) => DeviceAdminDataSource(),
);

final telephonyProvider = Provider<Telephony>((ref) => Telephony.instance);

final permissionOnboardingNotifierProvider =
    StateNotifierProvider<PermissionOnboardingNotifier, PermissionOnboardingState>(
  (ref) => PermissionOnboardingNotifier(
    deviceAdminDataSource: ref.watch(deviceAdminDataSourceProvider),
    telephony: ref.watch(telephonyProvider),
  ),
);