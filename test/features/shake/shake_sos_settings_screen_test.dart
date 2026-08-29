import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/shake/presentation/shake_sos_settings_screen.dart';

import '../../helpers/fakes.dart';

class FakeShakeSosService implements ShakeSosService {
  bool openedOverlaySettings = false;
  bool overlayGranted = false;
  bool openedBatterySettings = false;
  bool batteryWhitelisted = false;
  String? oemToken;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> openBatteryOptimizationSettings() async =>
      openedBatterySettings = true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => batteryWhitelisted;

  @override
  Future<String?> manufacturerToken() async => oemToken;

  @override
  Future<bool> canDrawOverlays() async => overlayGranted;

  @override
  Future<void> openOverlaySettings() async => openedOverlaySettings = true;

  @override
  Future<bool> startSosAlert() async => false;

  @override
  Future<void> stopSosAlert() async {}
}

void main() {
  Widget buildScreen(FakeShakeSosService service) {
    return ProviderScope(
      overrides: [
        shakeSosServiceProvider.overrideWithValue(service),
        preferencesServiceProvider.overrideWithValue(
          FakePreferencesService(),
        ),
      ],
      child: const MaterialApp(home: ShakeSosSettingsScreen()),
    );
  }

  testWidgets('shows the overlay-permission status and opens its settings',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService();
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Required to open the app from a shake when it is '
          'fully closed'),
      findsOneWidget,
    );

    await tester.tap(find.text('Display over other apps'));
    await tester.pumpAndSettle();

    expect(service.openedOverlaySettings, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows granted status when the overlay permission is on',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService()..overlayGranted = true;
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Shake SOS can open the app even when it is fully '
          'closed'),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('warns when GuardianHer is still battery-optimized and links '
      'to the system page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService();
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not protected yet'), findsOneWidget);

    await tester.tap(find.text('Battery optimization'));
    await tester.pumpAndSettle();

    expect(service.openedBatterySettings, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reports when battery optimization is already exempt',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService()..batteryWhitelisted = true;
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Allowed to run in the background'),
      findsOneWidget,
    );
    expect(find.textContaining('Not protected yet'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows MIUI Autostart guidance on Xiaomi-family devices',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService()..oemToken = 'miui';
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Xiaomi / Redmi / POCO: also enable Autostart'),
      findsOneWidget,
    );
    expect(find.textContaining('Samsung: remove'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows Samsung sleeping-apps guidance on Samsung devices',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService()..oemToken = 'samsung';
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Samsung: remove GuardianHer from Sleeping apps'),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows no extra hint for stock-Android makers', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeShakeSosService();
    await tester.pumpWidget(buildScreen(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('Autostart'), findsNothing);
    expect(find.textContaining('Sleeping apps'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}
