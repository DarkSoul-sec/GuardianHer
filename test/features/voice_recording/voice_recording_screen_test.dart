import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/voice_recording/application/voice_recording_providers.dart';
import 'package:guardianher/features/voice_recording/domain/voice_recording.dart';
import 'package:guardianher/features/voice_recording/domain/voice_recording_state.dart';
import 'package:guardianher/features/voice_recording/presentation/recording_detail_screen.dart';
import 'package:guardianher/features/voice_recording/presentation/voice_recording_screen.dart';

import '../../helpers/fakes.dart';

ProviderContainer _container() {
  final permissions = FakePermissionService()
    ..statuses[AppPermission.microphone] = PermissionStatus.granted;
  return createContainer(
    overrides: [
      permissionServiceProvider.overrideWithValue(permissions),
      voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
      voiceRecordingRepositoryProvider.overrideWithValue(
        FakeVoiceRecordingRepository(),
      ),
    ],
  );
}

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: VoiceRecordingScreen()),
  );
}

VoiceRecording _rec(String id) => VoiceRecording(
      id: id,
      path: '/tmp/$id.m4a',
      createdAt: DateTime.utc(2026, 9, 4, 20, 30),
      duration: const Duration(seconds: 42),
      displayName: 'Recording - $id',
    );

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
  });

  group('VoiceRecordingScreen', () {
    testWidgets('idle shows Start Recording', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Voice Recording'), findsWidgets);
      expect(find.text('Ready to record'), findsOneWidget);
      expect(find.text('Start Recording'), findsOneWidget);
      expect(find.text('No recordings yet.'), findsOneWidget);
    });

    testWidgets('start shows REC timer and stop', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      // In-app rationale precedes the permission request.
      expect(find.text('Microphone access'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('REC'), findsOneWidget);
      expect(find.text('Stop Recording'), findsOneWidget);
      expect(
        container.read(voiceRecordingControllerProvider),
        isA<VoiceRecordingActive>(),
      );

      // Cleanup: no live microphone/timers at teardown.
      await container.read(voiceRecordingControllerProvider.notifier).stopAndSave();
      await tester.pumpAndSettle();
    });

    testWidgets('denied permission shows recovery message', (tester) async {
      final permissions = FakePermissionService()
        ..statuses[AppPermission.microphone] = PermissionStatus.denied
        ..requestResults[AppPermission.microphone] = PermissionStatus.denied;
      final container = createContainer(
        overrides: [
          permissionServiceProvider.overrideWithValue(permissions),
          voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
          voiceRecordingRepositoryProvider.overrideWithValue(
            FakeVoiceRecordingRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('Microphone permission is required to record audio.'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('list shows recordings with play/share/delete', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await container
          .read(voiceRecordingRepositoryProvider)
          .save(_rec('a'));
      await container.read(voiceRecordingControllerProvider.notifier).refresh();

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Recording - a'), findsOneWidget);
      expect(find.text('00:42'), findsOneWidget);
      expect(find.byKey(const Key('voice-play-a')), findsOneWidget);
      expect(find.byKey(const Key('voice-share-a')), findsOneWidget);
      expect(find.byKey(const Key('voice-delete-a')), findsOneWidget);
    });

    testWidgets('delete asks for confirmation then removes', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await container
          .read(voiceRecordingRepositoryProvider)
          .save(_rec('a'));
      await container.read(voiceRecordingControllerProvider.notifier).refresh();

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('voice-delete-a')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this recording?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Recording - a'), findsNothing);
    });

    testWidgets('detail screen shows playback controls', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await container
          .read(voiceRecordingRepositoryProvider)
          .save(_rec('a'));
      await container.read(voiceRecordingControllerProvider.notifier).refresh();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: RecordingDetailScreen(recordingId: 'a'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recording - a'), findsWidgets);
      expect(find.byKey(const Key('voice-play-pause')), findsOneWidget);
      expect(find.byKey(const Key('voice-rename')), findsOneWidget);

      // Playback stops on dispose; no timers leak.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('navigates to /voice-recording via router', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.voiceRecording);
      await tester.pumpAndSettle();

      expect(find.byType(VoiceRecordingScreen), findsOneWidget);
    });
  });
}
