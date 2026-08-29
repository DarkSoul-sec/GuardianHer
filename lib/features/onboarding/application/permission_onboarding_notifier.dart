import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

import '../../data/datasources/device_admin_datasource.dart';

enum PermissionStep {
  location,
  smsPhone,
  notifications,
  overlay,
  batteryOptimization,
  deviceAdmin,
}

@immutable
class PermissionStatusItem {
  const PermissionStatusItem({
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
    required this.isCritical,
    this.isGranted = false,
    this.isPending = false,
  });

  final PermissionStep step;
  final String title;
  final String description;
  final String icon;
  final bool isCritical;
  final bool isGranted;
  final bool isPending;

  PermissionStatusItem copyWith({
    bool? isGranted,
    bool? isPending,
  }) {
    return PermissionStatusItem(
      step: step,
      title: title,
      description: description,
      icon: icon,
      isCritical: isCritical,
      isGranted: isGranted ?? this.isGranted,
      isPending: isPending ?? this.isPending,
    );
  }
}

@immutable
class PermissionOnboardingState {
  const PermissionOnboardingState({
    required this.items,
    this.currentStepIndex = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<PermissionStatusItem> items;
  final int currentStepIndex;
  final bool isLoading;
  final String? errorMessage;

  int get grantedCount => items.where((i) => i.isGranted).length;
  int get totalCount => items.length;
  double get progress => totalCount > 0 ? grantedCount / totalCount : 0.0;

  bool get criticalPermissionsGranted {
    return items
        .where((i) => i.isCritical)
        .every((i) => i.isGranted);
  }

  PermissionStatusItem? get currentItem {
    if (currentStepIndex < items.length) {
      return items[currentStepIndex];
    }
    return null;
  }

  PermissionOnboardingState copyWith({
    List<PermissionStatusItem>? items,
    int? currentStepIndex,
    bool? isLoading,
    String? errorMessage,
  }) {
    return PermissionOnboardingState(
      items: items ?? this.items,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class PermissionOnboardingNotifier extends StateNotifier<PermissionOnboardingState> {
  PermissionOnboardingNotifier({
    required this.deviceAdminDataSource,
    required Telephony telephony,
  }) : _telephony = telephony,
       super(_initialState()) {
    _checkAllPermissions();
  }

  final DeviceAdminDataSource deviceAdminDataSource;
  final Telephony _telephony;

  static PermissionOnboardingState _initialState() {
    return PermissionOnboardingState(
      items: [
        PermissionStatusItem(
          step: PermissionStep.location,
          title: 'Location Access',
          description: 'Live location sharing needs background location even when app is closed',
          icon: '📍',
          isCritical: true,
        ),
        PermissionStatusItem(
          step: PermissionStep.smsPhone,
          title: 'SMS & Phone',
          description: 'Auto-send emergency SOS messages to guardians without opening the SMS app',
          icon: '📱',
          isCritical: true,
        ),
        PermissionStatusItem(
          step: PermissionStep.notifications,
          title: 'Notifications',
          description: 'Required for SOS alerts and foreground service notifications',
          icon: '🔔',
          isCritical: true,
        ),
        PermissionStatusItem(
          step: PermissionStep.overlay,
          title: 'Display Over Other Apps',
          description: 'Allows SOS to launch from background when screen is locked',
          icon: '🔘',
          isCritical: false,
        ),
        PermissionStatusItem(
          step: PermissionStep.batteryOptimization,
          title: 'Battery Optimization',
          description: 'Prevents system from killing Shake SOS detector and foreground services',
          icon: '🔋',
          isCritical: false,
        ),
        PermissionStatusItem(
          step: PermissionStep.deviceAdmin,
          title: 'Device Administrator',
          description: 'Prevents attacker from uninstalling app during emergency',
          icon: '🛡️',
          isCritical: false,
        ),
      ],
    );
  }

  Future<void> _checkAllPermissions() async {
    state = state.copyWith(isLoading: true);

    final results = await Future.wait([
      _checkLocationPermission(),
      _checkSmsPhonePermission(),
      _checkNotificationPermission(),
      _checkOverlayPermission(),
      _checkBatteryOptimizationPermission(),
      _checkDeviceAdminPermission(),
    ]);

    final updatedItems = state.items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return item.copyWith(isGranted: results[index]);
    }).toList();

    state = state.copyWith(
      items: updatedItems,
      isLoading: false,
    );
  }

  Future<bool> _checkLocationPermission() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    final always = await Permission.locationAlways.status;
    return whenInUse.isGranted && always.isGranted;
  }

  Future<bool> _checkSmsPhonePermission() async {
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    return sms.isGranted && phone.isGranted;
  }

  Future<bool> _checkNotificationPermission() async {
    final notif = await Permission.notification.status;
    return notif.isGranted;
  }

  Future<bool> _checkOverlayPermission() async {
    final overlay = await Permission.systemAlertWindow.status;
    return overlay.isGranted;
  }

  Future<bool> _checkBatteryOptimizationPermission() async {
    final battery = await Permission.ignoreBatteryOptimizations.status;
    return battery.isGranted;
  }

  Future<bool> _checkDeviceAdminPermission() async {
    return await deviceAdminDataSource.isDeviceAdminActive();
  }

  Future<void> requestPermission(PermissionStep step) async {
    final index = state.items.indexWhere((i) => i.step == step);
    if (index == -1) return;

    state = state.copyWith(
      items: [
        ...state.items.sublist(0, index),
        state.items[index].copyWith(isPending: true),
        ...state.items.sublist(index + 1),
      ],
    );

    bool granted = false;

    try {
      switch (step) {
        case PermissionStep.location:
          granted = await _requestLocationPermission();
          break;
        case PermissionStep.smsPhone:
          granted = await _requestSmsPhonePermission();
          break;
        case PermissionStep.notifications:
          granted = await _requestNotificationPermission();
          break;
        case PermissionStep.overlay:
          granted = await _requestOverlayPermission();
          break;
        case PermissionStep.batteryOptimization:
          granted = await _requestBatteryOptimizationPermission();
          break;
        case PermissionStep.deviceAdmin:
          granted = await _requestDeviceAdminPermission();
          break;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to request permission: $e');
    }

    final updatedItems = state.items.asMap().entries.map((entry) {
      if (entry.key == index) {
        return entry.value.copyWith(isGranted: granted, isPending: false);
      }
      return entry.value;
    }).toList();

    state = state.copyWith(
      items: updatedItems,
      currentStepIndex: index + 1,
      errorMessage: null,
    );
  }

  Future<bool> _requestLocationPermission() async {
    var whenInUseStatus = await Permission.locationWhenInUse.request();
    if (!whenInUseStatus.isGranted) {
      return false;
    }
    var alwaysStatus = await Permission.locationAlways.request();
    return alwaysStatus.isGranted;
  }

  Future<bool> _requestSmsPhonePermission() async {
    var smsStatus = await Permission.sms.request();
    var phoneStatus = await Permission.phone.request();
    final telephonyPerms = await _telephony.requestPhoneAndSmsPermissions;
    return smsStatus.isGranted && phoneStatus.isGranted && telephonyPerms == true;
  }

  Future<bool> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> _requestOverlayPermission() async {
    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }

  Future<bool> _requestBatteryOptimizationPermission() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<bool> _requestDeviceAdminPermission() async {
    return await deviceAdminDataSource.requestDeviceAdminActivation();
  }

  Future<void> openAppSettingsForPermission(PermissionStep step) async {
    switch (step) {
      case PermissionStep.location:
        await openAppSettings();
        break;
      case PermissionStep.smsPhone:
        await openAppSettings();
        break;
      case PermissionStep.notifications:
        await openAppSettings();
        break;
      case PermissionStep.overlay:
        await Permission.systemAlertWindow.request();
        break;
      case PermissionStep.batteryOptimization:
        await Permission.ignoreBatteryOptimizations.request();
        break;
      case PermissionStep.deviceAdmin:
        // Device admin settings opened via the channel
        await deviceAdminDataSource.requestDeviceAdminActivation();
        break;
    }
    // Re-check after settings
    await _checkAllPermissions();
  }

  void moveToNextStep() {
    final nextIndex = state.currentStepIndex + 1;
    if (nextIndex < state.items.length) {
      state = state.copyWith(currentStepIndex: nextIndex);
    }
  }

  Future<void> refresh() async {
    await _checkAllPermissions();
  }
}