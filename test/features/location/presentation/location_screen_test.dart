import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/presentation/location_screen.dart';

import '../../../helpers/fakes.dart';
import '../../sos/sos_test_fakes.dart';

void main() {
  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LocationScreen()),
    );
  }

  testWidgets('shows the idle launch view', (tester) async {
    final container = createContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    expect(find.text('My Location'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Get Current Location'),
        findsOneWidget);
  });

  testWidgets('captures a location and shows its honest details',
      (tester) async {
    final container = createContainer(
      overrides: [
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Location captured'), findsOneWidget);
    expect(find.text('Latitude'), findsOneWidget);
    expect(find.text('Longitude'), findsOneWidget);
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('12.345678'), findsOneWidget);
    expect(find.text('98.765432'), findsOneWidget);
    expect(find.text('15 m'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(find.text('Share Location'), findsOneWidget);
  });

  testWidgets('explains permission before requesting it when retryable',
      (tester) async {
    final location = FakeLocationService(
      permission: PermissionStatus.denied,
      requestPermissionResult: PermissionStatus.granted,
    );
    final container = createContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.denied,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();

    // The contextual explanation precedes any request.
    expect(find.text('Allow location access?'), findsOneWidget);
    expect(location.permissionRequestCount, 0);

    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('My Location'), findsOneWidget);
    expect(location.permissionRequestCount, 0);
  });

  testWidgets('continuing from the explanation captures the location',
      (tester) async {
    final location = FakeLocationService(
      permission: PermissionStatus.denied,
      requestPermissionResult: PermissionStatus.granted,
    );
    final container = createContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.denied,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();

    expect(location.permissionRequestCount, 1);
    expect(find.text('Location captured'), findsOneWidget);
  });

  testWidgets('permanently denied permission offers settings recovery',
      (tester) async {
    final container = createContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(
          FakeLocationService(permission: PermissionStatus.permanentlyDenied),
        ),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] =
                PermissionStatus.permanentlyDenied,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();

    expect(find.text('Allow location access?'), findsNothing);
    expect(
      find.text('Location permission is off. Open Settings to allow it.'),
      findsOneWidget,
    );
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('disabled location services offer settings recovery',
      (tester) async {
    final container = createContainer(
      overrides: [
        locationServiceProvider
            .overrideWithValue(FakeLocationService(enabled: false)),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();

    expect(find.text('Location services are turned off.'), findsOneWidget);
    expect(find.text('Turn on location'), findsOneWidget);
  });

  testWidgets('a failed fix offers a retry', (tester) async {
    final container = createContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(
          FakeLocationService(failure: const LocationTimeoutFailure()),
        ),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.text('The location could not be determined. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('open in maps launches the map for the captured point',
      (tester) async {
    final map = FakeMapService();
    final container = createContainer(
      overrides: [
        mapServiceProvider.overrideWithValue(map),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Open in Maps'));
    await tester.pump();

    expect(map.openCalls, 1);
    expect(map.lastOpened, testLocationPoint);
  });

  testWidgets('a failed map launch is reported truthfully', (tester) async {
    final container = createContainer(
      overrides: [
        mapServiceProvider.overrideWithValue(
          FakeMapService(result: const Err(UnableToOpenMapsFailure())),
        ),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Open in Maps'));
    await tester.pump();

    expect(find.text('Unable to open maps.'), findsOneWidget);
  });

  testWidgets('share opens the SMS composer with no recipient', (tester) async {
    final sms = FakeSmsService();
    final container = createContainer(
      overrides: [
        smsServiceProvider.overrideWithValue(sms),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Share Location'));
    await tester.pump();

    expect(sms.opened, hasLength(1));
    expect(sms.opened.single.phoneNumber, isEmpty);
    expect(sms.opened.single.body, contains('maps.google.com'));
  });
}