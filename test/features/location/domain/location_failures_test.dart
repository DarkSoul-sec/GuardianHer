import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';

void main() {
  group('LocationFailure', () {
    test('every kind is a Failure and carries a message and code', () {
      const failures = <Failure>[
        LocationServicesDisabledFailure(),
        LocationPermissionMissingFailure(),
        InvalidLocationCoordinatesFailure(),
        LocationTimeoutFailure(),
        LocationUnavailableFailure(),
      ];
      for (final failure in failures) {
        expect(failure, isA<LocationFailure>());
        expect(failure.message, isNotEmpty);
        expect(failure.code, isNotNull);
      }
    });

    test('each kind has a distinct runtime type', () {
      const failures = <Failure>[
        LocationServicesDisabledFailure(),
        LocationPermissionMissingFailure(),
        InvalidLocationCoordinatesFailure(),
        LocationTimeoutFailure(),
        LocationUnavailableFailure(),
      ];
      final types = failures.map((f) => f.runtimeType).toSet();
      expect(types.length, failures.length);
    });

    test('permission-missing failure has stable defaults', () {
      const failure = LocationPermissionMissingFailure();
      expect(failure.message, 'Location access is not configured on this device.');
      expect(failure.code, 'location_permission_missing');
    });
  });
}