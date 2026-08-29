import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/live_location/application/live_location_providers.dart';
import 'package:guardianher/features/live_location/data/live_location_api_client.dart';
import 'package:guardianher/features/live_location/domain/live_location_failures.dart';
import 'package:guardianher/features/live_location/presentation/live_location_screen.dart';

import '../../../helpers/fakes.dart';

void main() {
  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LiveLocationScreen()),
    );
  }

  ProviderContainer configuredContainer({
    FakeLiveLocationApiClient? api,
  }) {
    return createContainer(
      overrides: [
        liveLocationApiClientProvider.overrideWithValue(
          api ?? (FakeLiveLocationApiClient()..configured = true),
        ),
        liveLocationUpdatesProvider
            .overrideWithValue(FakeLiveLocationUpdates()),
        liveLocationForegroundServiceProvider
            .overrideWithValue(FakeLiveLocationForegroundService()),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
      ],
    );
  }

  testWidgets('idle view offers every duration and the start action',
      (tester) async {
    final container = configuredContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    expect(find.text('Start sharing'), findsOneWidget);
    for (final minutes in ['15 min', '30 min', '60 min', '120 min']) {
      expect(find.text(minutes), findsOneWidget);
    }
    // The visible-notification promise is part of the honest UI.
    expect(find.text('A notification stays while sharing'), findsOneWidget);
  });

  testWidgets('an unconfigured build explains itself after a start attempt',
      (tester) async {
    final container = createContainer(); // API fake stays unconfigured
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.text('Start sharing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Live sharing is not available in this build.'),
      findsOneWidget,
    );
  });

  testWidgets('active view shows LIVE state, share row and stop flow',
      (tester) async {
    final container = configuredContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.text('Start sharing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('SMS'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);

    // Teardown so no timer leaks out of the widget test.
    await tester.tap(find.text('Stop sharing'));
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Stop sharing'),
      ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Live location sharing stopped.'), findsOneWidget);
  });

  testWidgets('offline session shows the connection-unavailable truth',
      (tester) async {
    final api = FakeLiveLocationApiClient()
      ..configured = true
      ..createResult = () => Err<LiveSessionCreation>(
            LiveLocationFailure(LiveLocationFailureType.networkUnavailable),
          );
    final container = configuredContainer(api: api);
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    await tester.tap(find.text('Start sharing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('Connection unavailable'), findsWidgets);
    // No URL yet — the honest "link later" line replaces the share row.
    expect(find.textContaining('Link will appear'), findsOneWidget);

    // Teardown.
    await tester.tap(find.text('Stop sharing'));
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Stop sharing'),
      ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
