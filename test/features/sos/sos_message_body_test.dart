import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  group('sosMessageBodyProvider', () {
    test('uses the generic body when no fix was captured', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final body = container.read(sosMessageBodyProvider);
      expect(body, 'I need help. This is an automated message from GuardianHer. '
          'Please contact me.');
      expect(body, isNot(contains('maps.google.com')));
    });

    test('appends a shareable current-location link after a capture', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(locationControllerProvider.notifier).captureLocation();
      final body = container.read(sosMessageBodyProvider);
      expect(body, contains('My location:'));
      expect(body, contains('https://maps.google.com/?q=12.345678,98.765432'));
      expect(body, contains('I need help.'));
    });
  });
}