import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/result/result.dart';

void main() {
  group('Result', () {
    test('Ok holds a value and reports success', () {
      const ok = Ok<int>(42);
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(ok.value, 42);
    });

    test('Err holds a failure and reports failure', () {
      const err = Err<int>(UnexpectedFailure());
      expect(err.isErr, isTrue);
      expect(err.isOk, isFalse);
      expect(err.failure, isA<UnexpectedFailure>());
    });

    test('fold maps an Ok value', () {
      const ok = Ok<int>(2);
      expect(ok.fold((v) => 'value=$v', (f) => 'failed'), 'value=2');
    });

    test('fold surfaces the failure message on Err', () {
      const err = Err<int>(PermissionDeniedFailure());
      expect(
        err.fold((v) => 'value=$v', (f) => f.message),
        'Permission was denied.',
      );
    });

    test('getOrNull returns the value on Ok', () {
      const ok = Ok<String>('here');
      expect(ok.getOrNull(), 'here');
    });

    test('getOrNull returns null on Err', () {
      const err = Err<String>(PlatformFailure());
      expect(err.getOrNull(), isNull);
    });
  });
}