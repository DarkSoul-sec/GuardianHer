import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/app_info_service.dart';
import 'package:guardianher/core/platform/call_service.dart';
import 'package:guardianher/core/platform/location_service.dart';
import 'package:guardianher/core/platform/map_service.dart';
import 'package:guardianher/core/platform/notification_service.dart';
import 'package:guardianher/core/platform/preferences_service.dart';
import 'package:guardianher/core/platform/sms_service.dart';
import 'package:guardianher/core/platform/vibration_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/security/data_cleanup_service.dart';
import 'package:guardianher/core/security/secure_storage_service.dart';

class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  group('core service providers', () {
    test('secureStorageServiceProvider can be overridden with a fake', () async {
      final mock = MockSecureStorageService();
      when(() => mock.read('pin')).thenAnswer((_) async => '1234');

      final container = ProviderContainer(
        overrides: [secureStorageServiceProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);

      final service = container.read(secureStorageServiceProvider);
      expect(service, isA<SecureStorageService>());
      expect(await service.read('pin'), '1234');
    });

    test('Phase 1 core providers resolve to their implementations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(secureStorageServiceProvider),
          isA<SecureStorageService>());
      expect(container.read(permissionServiceProvider),
          isA<PermissionService>());
      expect(container.read(preferencesServiceProvider),
          isA<PreferencesService>());
      expect(container.read(appInfoServiceProvider), isA<AppInfoService>());
      expect(container.read(dataCleanupServiceProvider),
          isA<DataCleanupService>());
    });

    test('Phase 3B emergency services resolve to implementations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(callServiceProvider), isA<CallService>());
      expect(container.read(smsServiceProvider), isA<SmsService>());
      expect(container.read(notificationServiceProvider),
          isA<NotificationService>());
      expect(container.read(vibrationServiceProvider),
          isA<VibrationService>());
    });

    test('Phase 3C location services resolve to implementations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(locationServiceProvider),
          isA<LocationService>());
      expect(container.read(mapServiceProvider), isA<MapService>());
    });
  });
}