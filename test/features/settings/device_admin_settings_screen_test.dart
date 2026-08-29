import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/settings/presentation/device_admin_settings_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  Widget buildScreen(FakeDeviceAdminService service) {
    return ProviderScope(
      overrides: [deviceAdminServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: DeviceAdminSettingsScreen()),
    );
  }

  testWidgets('shows inactive status and activates on tap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeDeviceAdminService();
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not a device administrator'),
      findsOneWidget,
    );
    expect(find.text('Activate device administrator'), findsOneWidget);
    expect(find.text('Deactivate device administrator'), findsNothing);

    await tester.tap(find.text('Activate device administrator'));
    await tester.pumpAndSettle();

    expect(service.activationRequests, 1);
    expect(service.active, isTrue);
    expect(
      find.textContaining('active device administrator'),
      findsOneWidget,
    );
    expect(find.text('Deactivate device administrator'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows active status and deactivates on tap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeDeviceAdminService()..active = true;
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('active device administrator'),
      findsOneWidget,
    );
    expect(find.text('Deactivate device administrator'), findsOneWidget);

    await tester.tap(find.text('Deactivate device administrator'));
    await tester.pumpAndSettle();

    expect(service.deactivations, 1);
    expect(service.active, isFalse);
    expect(
      find.textContaining('not a device administrator'),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('is hidden on non-Android platforms', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = FakeDeviceAdminService();
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Activate device administrator'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}