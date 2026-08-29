import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/live_location/application/live_location_providers.dart';
import 'package:guardianher/features/live_location/data/live_location_api_client.dart';
import 'package:guardianher/features/live_location/domain/live_location_failures.dart';
import 'package:guardianher/features/live_location/domain/live_location_session.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

void main() {
  testWidgets('an active SOS starts an emergency live session and links it',
      (tester) async {
    final liveApi = FakeLiveLocationApiClient()..configured = true;
    final fixture = createSosContainer(
      extraOverrides: [
        liveLocationApiClientProvider.overrideWithValue(liveApi),
      ],
    );
    addTearDown(fixture.container.dispose);
    // Instantiate the action controller so its state listener is active.
    fixture.container.read(sosActionsControllerProvider);

    fixture.container.read(sosControllerProvider.notifier).startSos();
    // Countdown (3 s) must elapse before the session is active.
    await tester.pump(const Duration(seconds: 4));
    fixture.timer.fireComplete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fixture.container.read(sosControllerProvider), isA<SosActive>());
    expect(liveApi.createCalls, 1);
    expect(liveApi.lastCreateInterval, LiveUpdateInterval.sos);

    final body = fixture.container.read(sosMessageBodyProvider);
    expect(body, contains('Live location:'));
    expect(body, contains('https://live.example.org/live/'));
    expect(body, contains('This link expires at'));

    // Teardown: stop the emergency share and end the SOS session.
    await fixture.container
        .read(liveLocationControllerProvider.notifier)
        .stopSession();
    await tester.pump(const Duration(milliseconds: 50));
    fixture.container.read(sosControllerProvider.notifier).cancelSos();
    fixture.timer.fireComplete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('a failing live backend never breaks the SOS message',
      (tester) async {
    final liveApi = FakeLiveLocationApiClient()
      ..configured = true
      ..createResult = () => Err<LiveSessionCreation>(
            LiveLocationFailure(LiveLocationFailureType.networkUnavailable),
          );
    final fixture = createSosContainer(
      extraOverrides: [
        liveLocationApiClientProvider.overrideWithValue(liveApi),
      ],
    );
    addTearDown(fixture.container.dispose);
    // Instantiate the action controller so its state listener is active.
    fixture.container.read(sosActionsControllerProvider);

    fixture.container.read(sosControllerProvider.notifier).startSos();
    await tester.pump(const Duration(seconds: 4));
    fixture.timer.fireComplete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fixture.container.read(sosControllerProvider), isA<SosActive>());
    expect(liveApi.createCalls, 1);
    // The body stays the plain SOS text — no half-truths about a link.
    final body = fixture.container.read(sosMessageBodyProvider);
    expect(body, contains('I need help.'));
    expect(body, isNot(contains('Live location:')));

    // Teardown: stop the emergency share and end the SOS session.
    await fixture.container
        .read(liveLocationControllerProvider.notifier)
        .stopSession();
    await tester.pump(const Duration(milliseconds: 50));
    fixture.container.read(sosControllerProvider.notifier).cancelSos();
    fixture.timer.fireComplete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
