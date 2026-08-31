import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/features/onboarding/data/datasources/device_admin_datasource.dart';
import 'package:guardianher/core/platform/direct_sms_service.dart';
import 'package:guardianher/features/shake/application/shake_sos_providers.dart';

enum PermissionStep {
  location,
  sms,
  phone,
  notifications,
  overlay,
  shakeSos,
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
    required this.directSmsService,
    required this.shakeSosService,
    required this.ref,
  }) : super(_initialState()) {
    _checkAllPermissions();
    _initLifecycleListener();
  }

  final DeviceAdminDataSource deviceAdminDataSource;
  final DirectSmsService directSmsService;
  final ShakeSosService shakeSosService;
  final Ref ref;
  AppLifecycleListener? _lifecycleListener;

  void _initLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onResume: _onAppResume,
      onDetach: _onAppDetach,
    );
  }

  Future<void> _onAppResume() async {
    // Re-check all permissions when app resumes (e.g., after returning from Settings)
    await _checkAllPermissions();
  }

  void _onAppDetach() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  static PermissionOnboardingState _initialState() {
    return PermissionOnboardingState(
      items: [
        PermissionStatusItem(
          step: PermissionStep.location,
          title: 'Location Access',
          description: 'Required for SOS location capture and live location sharing',
          icon: '📍',
          isCritical: true,
        ),
        PermissionStatusItem(
          step: PermissionStep.sms,
          title: 'SMS Permission',
          description: 'Required to automatically send emergency SOS messages to guardians',
          icon: '📩',
          isCritical: true,
        ),
        PermissionStatusItem(
          step: PermissionStep.phone,
          title: 'Phone Permission',
          description: 'Allows making emergency calls directly from the app',
          icon: '📞',
          isCritical: false,
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
          step: PermissionStep.shakeSos,
          title: 'Shake SOS',
          description: 'Activate emergency SOS by shaking your phone when you need help',
          icon: '📳',
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

    final shakeSosEnabled = ref.read(shakeSosEnabledProvider);

    final results = await Future.wait([
      _checkLocationPermission(),
      _checkSmsPermission(),
      _checkPhonePermission(),
      _checkNotificationPermission(),
      _checkOverlayPermission(),
      Future.value(shakeSosEnabled),
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
    // The app only requests foreground location (ACCESS_FINE_LOCATION + ACCESS_COARSE_LOCATION).
    // ACCESS_BACKGROUND_LOCATION is NOT declared in the manifest and is NOT required.
    // Live location sharing uses a foreground service with location foreground type,
    // which is the documented alternative to ACCESS_BACKGROUND_LOCATION.
    final whenInUse = await Permission.locationWhenInUse.status;
    return whenInUse.isGranted;
  }

  Future<bool> _checkSmsPermission() async {
    final sms = await Permission.sms.status;
    return sms.isGranted;
  }

  Future<bool> _checkPhonePermission() async {
    final phone = await Permission.phone.status;
    return phone.isGranted;
  }

  Future<bool> _checkNotificationPermission() async {
    final notif = await Permission.notification.status;
    return notif.isGranted;
  }

  Future<bool> _checkOverlayPermission() async {
    final overlay = await Permission.systemAlertWindow.status;
    return overlay.isGranted;
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
        case PermissionStep.sms:
          granted = await _requestSmsPermission();
          break;
        case PermissionStep.phone:
          granted = await _requestPhonePermission();
          break;
        case PermissionStep.notifications:
          granted = await _requestNotificationPermission();
          break;
        case PermissionStep.overlay:
          granted = await _requestOverlayPermission();
          break;
        case PermissionStep.shakeSos:
          granted = await _requestShakeSosPermission();
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

  Future<bool> _requestSmsPermission() async {
    var smsStatus = await Permission.sms.request();
    // Check SIM readiness via native channel
    final simReady = await directSmsService.checkSimReady();
    return smsStatus.isGranted && simReady;
  }

  Future<bool> _requestPhonePermission() async {
    var phoneStatus = await Permission.phone.request();
    return phoneStatus.isGranted;
  }

  Future<bool> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> _requestOverlayPermission() async {
    if (isShakeSosSupported) {
      await shakeSosService.openOverlaySettings();
      // Re-check after opening settings
      await Future.delayed(const Duration(milliseconds: 500));
      return await _checkOverlayPermission();
    }
    return false;
  }

  Future<bool> _requestShakeSosPermission() async {
    if (isShakeSosSupported) {
      await ref.read(shakeSosEnabledProvider.notifier).setEnabled(true);
      // Re-check after enabling
      await Future.delayed(const Duration(milliseconds: 500));
      return ref.read(shakeSosEnabledProvider);
    }
    return false;
  }

  Future<bool> _requestDeviceAdminPermission() async {
    return await deviceAdminDataSource.requestDeviceAdminActivation();
  }

  Future<void> openAppSettingsForPermission(PermissionStep step) async {
    switch (step) {
      case PermissionStep.location:
        await openAppSettings();
        break;
      case PermissionStep.sms:
        await openAppSettings();
        break;
      case PermissionStep.phone:
        await openAppSettings();
        break;
      case PermissionStep.notifications:
        await openAppSettings();
        break;
      case PermissionStep.overlay:
        if (isShakeSosSupported) {
          await shakeSosService.openOverlaySettings();
        }
        break;
      case PermissionStep.shakeSos:
        // Shake SOS is managed in-app, not via system settings
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