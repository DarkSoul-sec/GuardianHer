import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';

void main() {
  group('Failure model', () {
    test('all failure kinds extend Failure and carry a message', () {
      const failures = <Failure>[
        UnexpectedFailure(),
        PlatformFailure(),
        StorageFailure(),
        PermissionDeniedFailure(),
      ];
      for (final failure in failures) {
        expect(failure.message, isNotEmpty);
      }
    });

    test('UnexpectedFailure has a stable default message and code', () {
      const failure = UnexpectedFailure();
      expect(failure.message, 'An unexpected error occurred.');
      expect(failure.code, 'unexpected');
    });

    test('custom message and code are preserved', () {
      const failure = PermissionDeniedFailure('Location access is required.');
      expect(failure.message, 'Location access is required.');
      expect(failure.code, 'permission_denied');
    });

    test('each failure kind has a distinct runtime type', () {
      const failures = <Failure>[
        UnexpectedFailure(),
        PlatformFailure(),
        StorageFailure(),
        PermissionDeniedFailure(),
      ];
      final types = failures.map((f) => f.runtimeType).toSet();
      expect(types.length, failures.length);
    });
  });
}