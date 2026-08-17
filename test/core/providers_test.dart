import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:guardianher/core/providers.dart';
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

    test('core providers are registered until implementations arrive', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(locationServiceProvider),
        throwsUnimplementedError,
      );
      expect(
        () => container.read(permissionServiceProvider),
        throwsUnimplementedError,
      );
      expect(
        () => container.read(secureStorageServiceProvider),
        throwsUnimplementedError,
      );
    });
  });
}