import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/data/permission_status_mapper.dart';

void main() {
  group('mapAppPermission', () {
    test('maps every AppPermission to a platform permission', () {
      for (final permission in AppPermission.values) {
        expect(
          () => mapAppPermission(permission),
          returnsNormally,
          reason: '$permission must map to a platform permission',
        );
      }
    });
  });

  group('mapPlatformPermissionStatus', () {
    test('maps platform statuses to the domain status', () {
      expect(mapPlatformPermissionStatus(ph.PermissionStatus.granted),
          PermissionStatus.granted);
      expect(mapPlatformPermissionStatus(ph.PermissionStatus.denied),
          PermissionStatus.denied);
      expect(mapPlatformPermissionStatus(ph.PermissionStatus.restricted),
          PermissionStatus.restricted);
      expect(mapPlatformPermissionStatus(ph.PermissionStatus.limited),
          PermissionStatus.limited);
      expect(
        mapPlatformPermissionStatus(ph.PermissionStatus.permanentlyDenied),
        PermissionStatus.permanentlyDenied,
      );
    });

    test('treats provisional (iOS) as denied', () {
      expect(mapPlatformPermissionStatus(ph.PermissionStatus.provisional),
          PermissionStatus.denied);
    });
  });
}