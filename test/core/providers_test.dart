import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/app_info_service.dart';
import 'package:guardianher/core/platform/biometric_service.dart';
import 'package:guardianher/core/platform/preferences_service.dart';
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
      expect(container.read(biometricServiceProvider), isA<BiometricService>());
      expect(container.read(appInfoServiceProvider), isA<AppInfoService>());
      expect(container.read(dataCleanupServiceProvider),
          isA<DataCleanupService>());
    });

    test('unused Phase 2 services still throw until implemented', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(locationServiceProvider),
          throwsUnimplementedError);
      expect(
          () => container.read(callServiceProvider), throwsUnimplementedError);
      expect(() => container.read(smsServiceProvider), throwsUnimplementedError);
      expect(() => container.read(mapServiceProvider), throwsUnimplementedError);
      expect(() => container.read(notificationServiceProvider),
          throwsUnimplementedError);
    });
  });
}