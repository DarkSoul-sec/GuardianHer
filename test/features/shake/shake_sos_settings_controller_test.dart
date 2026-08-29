import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/shake/application/shake_sos_providers.dart';
import 'package:guardianher/features/shake/application/shake_sos_settings_controller.dart';

import '../../helpers/fakes.dart';

class FakeShakeSosService implements ShakeSosService {
  int started = 0;
  int stopped = 0;
  bool openedBatterySettings = false;
  bool openedOverlaySettings = false;
  bool overlayGranted = false;

  @override
  Future<void> start() async => started++;

  @override
  Future<void> stop() async => stopped++;

  @override
  Future<void> openBatteryOptimizationSettings() async =>
      openedBatterySettings = true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<String?> manufacturerToken() async => null;

  @override
  Future<bool> canDrawOverlays() async => overlayGranted;

  @override
  Future<void> openOverlaySettings() async => openedOverlaySettings = true;

  @override
  Future<bool> startSosAlert() async => false;

  @override
  Future<void> stopSosAlert() async {}
}

void main() {
  late FakeShakeSosService service;
  late FakePreferencesService preferences;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        shakeSosServiceProvider.overrideWithValue(service),
        preferencesServiceProvider.overrideWithValue(preferences),
      ],
    );
  }

  setUp(() {
    // The shake detector is Android-only; tests run on the host platform.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    service = FakeShakeSosService();
    preferences = FakePreferencesService();
    container = buildContainer();
  });

  tearDown(() {
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  group('ShakeSosSettingsController', () {
    test('starts disabled', () {
      expect(container.read(shakeSosEnabledProvider), isFalse);
      expect(service.started, 0);
    });

    test('enabling starts the service and persists the choice', () async {
      await container
          .read(shakeSosEnabledProvider.notifier)
          .setEnabled(true);

      expect(container.read(shakeSosEnabledProvider), isTrue);
      expect(service.started, 1);
      expect(service.stopped, 0);
      expect(
        await preferences.getBool(shakeSosEnabledPreferenceKey),
        isTrue,
      );
    });

    test('disabling stops the service and persists the choice', () async {
      await container
          .read(shakeSosEnabledProvider.notifier)
          .setEnabled(true);
      await container
          .read(shakeSosEnabledProvider.notifier)
          .setEnabled(false);

      expect(container.read(shakeSosEnabledProvider), isFalse);
      expect(service.started, 1);
      expect(service.stopped, 1);
      expect(
        await preferences.getBool(shakeSosEnabledPreferenceKey),
        isFalse,
      );
    });

    test('restores a persisted enabled flag and re-anchors the service',
        () async {
      await preferences.setBool(shakeSosEnabledPreferenceKey, true);
      container.dispose();
      container = buildContainer();

      // Starts off, then flips once the async restore completes.
      expect(container.read(shakeSosEnabledProvider), isFalse);
      await pumpEventQueue();

      expect(container.read(shakeSosEnabledProvider), isTrue);
      expect(service.started, 1);
    });

    test('does nothing on non-Android platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final nonAndroidContainer = buildContainer();
      addTearDown(nonAndroidContainer.dispose);

      expect(nonAndroidContainer.read(shakeSosEnabledProvider), isFalse);
      await nonAndroidContainer
          .read(shakeSosEnabledProvider.notifier)
          .setEnabled(true);

      expect(nonAndroidContainer.read(shakeSosEnabledProvider), isFalse);
      expect(service.started, 0);
      expect(service.stopped, 0);
    });
  });
}