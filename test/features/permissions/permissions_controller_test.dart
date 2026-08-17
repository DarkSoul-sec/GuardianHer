import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/permissions/application/permissions_providers.dart';
import 'package:guardianher/features/permissions/domain/permission_descriptor.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakePermissionService service;

  ProviderContainer container() {
    service = FakePermissionService();
    return ProviderContainer(
      overrides: [
        ...defaultOverrides(
          overrides: [permissionServiceProvider.overrideWithValue(service)],
        ),
      ],
    );
  }

  group('PermissionsController', () {
    test('builds an entry per descriptor with mapped statuses', () async {
      final c = container();
      addTearDown(c.dispose);
      service.statuses[AppPermission.location] = PermissionStatus.granted;
      service.statuses[AppPermission.notifications] =
          PermissionStatus.permanentlyDenied;

      final entries = await c.read(permissionsControllerProvider.future);

      expect(entries.length, permissionDescriptors.length);
      final location = entries.firstWhere(
        (e) => e.descriptor.permission == AppPermission.location,
      );
      expect(location.status, PermissionStatus.granted);
      expect(location.descriptor.title, 'Location');
      expect(location.requestable, isFalse);

      final notifications = entries.firstWhere(
        (e) => e.descriptor.permission == AppPermission.notifications,
      );
      expect(notifications.status, PermissionStatus.permanentlyDenied);
      expect(notifications.permanentlyDenied, isTrue);
    });

    test('request updates the entry status', () async {
      final c = container();
      addTearDown(c.dispose);
      service.statuses[AppPermission.location] = PermissionStatus.denied;

      final notifier = c.read(permissionsControllerProvider.notifier);
      await notifier.request(AppPermission.location);

      final entries = c.read(permissionsControllerProvider).valueOrNull!;
      final location = entries.firstWhere(
        (e) => e.descriptor.permission == AppPermission.location,
      );
      expect(location.status, PermissionStatus.granted);
    });

    test('openSettings delegates to the service', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(permissionsControllerProvider.notifier).openSettings();

      expect(service.openSettingsCalls, 1);
    });
  });

  group('permission catalog', () {
    test('no permission is requestable in Phase 1', () {
      expect(
        permissionDescriptors.every((d) => !d.requestable),
        isTrue,
        reason: 'Only safe/required permissions may be requested.',
      );
    });
  });
}