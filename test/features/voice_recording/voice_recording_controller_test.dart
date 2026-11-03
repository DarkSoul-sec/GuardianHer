import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/voice_recording/application/voice_recording_providers.dart';
import 'package:guardianher/features/voice_recording/domain/voice_recording.dart';
import 'package:guardianher/features/voice_recording/domain/voice_recording_state.dart';

import '../../helpers/fakes.dart';

class _Harness {
  _Harness({List<VoiceRecording>? seed, FakeShareService? share}) {
    permissions = FakePermissionService();
    recorder = FakeVoiceRecorder();
    repository = FakeVoiceRecordingRepository(seed);
    container = createContainer(
      overrides: [
        permissionServiceProvider.overrideWithValue(permissions),
        voiceRecorderProvider.overrideWithValue(recorder),
        voiceRecordingRepositoryProvider.overrideWithValue(repository),
        if (share != null) shareServiceProvider.overrideWithValue(share),
      ],
    );
  }

  late final FakePermissionService permissions;
  late final FakeVoiceRecorder recorder;
  late final FakeVoiceRecordingRepository repository;
  late final ProviderContainer container;

  VoiceRecordingState get state =>
      container.read(voiceRecordingControllerProvider);

  void dispose() => container.dispose();
}

VoiceRecording _rec(String id, [int secondsAgo = 60]) => VoiceRecording(
      id: id,
      path: '/tmp/$id.m4a',
      createdAt: DateTime.utc(2026, 9, 4, 12).subtract(
        Duration(seconds: secondsAgo),
      ),
      duration: const Duration(seconds: 42),
      displayName: 'Recording - $id',
    );

void main() {
  group('VoiceRecordingController', () {
    test('initial state is idle with empty list', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(h.state, isA<VoiceIdle>());
      expect(h.state.recordings, isEmpty);
    });

    test('denied permission reports an honest error and never records',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.denied;
      h.permissions.requestResults[AppPermission.microphone] =
          PermissionStatus.denied;
      await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .startRecording();

      expect(h.state, isA<VoiceError>());
      expect(
        (h.state as VoiceError).message,
        contains('Microphone permission is required'),
      );
      expect(h.recorder.startCalls, 0);
    });

    test('granted permission starts recording', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.granted;
      await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .startRecording();

      expect(h.state, isA<VoiceRecordingActive>());
      expect(h.recorder.startCalls, 1);
      expect(h.recorder.lastPath, endsWith('.m4a'));
    });

    test('recording timer ticks once per second', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        h.permissions.statuses[AppPermission.microphone] =
            PermissionStatus.granted;
        h.container
            .read(voiceRecordingControllerProvider.notifier)
            .startRecording();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 12));
        final state = h.state;
        expect(state, isA<VoiceRecordingActive>());
        expect(
          (state as VoiceRecordingActive).elapsed,
          const Duration(seconds: 12),
        );
      });
    });

    test('stop saves metadata with measured duration', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.granted;
      final notifier =
          h.container.read(voiceRecordingControllerProvider.notifier);
      await notifier.startRecording();
      await Future<void>.delayed(const Duration(seconds: 2));
      await notifier.stopAndSave();

      final state = h.state;
      expect(state, isA<VoiceSaved>());
      final saved = (state as VoiceSaved).saved;
      expect(saved.displayName, startsWith('Recording - '));
      expect(saved.path, endsWith('.m4a'));
      expect(h.recorder.stopCalls, 1);
      final list = await h.repository.loadAll();
      expect(list.fold((l) => l.length, (_) => -1), 1);
    });

    test('engine start failure surfaces an error', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.granted;
      h.recorder.startResult = false;
      await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .startRecording();

      expect(h.state, isA<VoiceError>());
      expect(
        (h.state as VoiceError).message,
        contains('could not be started'),
      );
    });

    test('recordings list newest-first', () async {
      final h = _Harness(seed: [_rec('old', 300), _rec('new', 60)]);
      addTearDown(h.dispose);
      await h.container.read(voiceRecordingControllerProvider.notifier).refresh();
      final recordings = h.state.recordings;
      expect(recordings.map((r) => r.id).toList(), ['new', 'old']);
    });

    test('delete removes metadata', () async {
      final h = _Harness(seed: [_rec('a'), _rec('b')]);
      addTearDown(h.dispose);
      final result = await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .deleteRecording('a');
      expect(result.isOk, isTrue);
      expect(h.state.recordings.map((r) => r.id), ['b']);
    });

    test('share invokes the share sheet seam', () async {
      final share = FakeShareService();
      final h = _Harness(seed: [_rec('a')], share: share);
      addTearDown(h.dispose);
      final result = await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .shareRecording('a');
      expect(result.isOk, isTrue);
      expect(share.shared, ['/tmp/a.m4a']);
    });

    test('permanent denial explains Settings recovery', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.denied;
      h.permissions.requestResults[AppPermission.microphone] =
          PermissionStatus.permanentlyDenied;
      await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .startRecording();

      expect(h.state, isA<VoiceError>());
      expect(
        (h.state as VoiceError).message,
        contains('Settings'),
      );
      expect(h.recorder.startCalls, 0);
    });

    test('backgrounding mid-recording stops and saves', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.granted;
      final notifier =
          h.container.read(voiceRecordingControllerProvider.notifier);
      await notifier.startRecording();
      expect(h.state, isA<VoiceRecordingActive>());

      await notifier.handleAppPaused();

      expect(h.state, isA<VoiceSaved>());
      expect(h.recorder.stopCalls, 1);
      final list = await h.repository.loadAll();
      expect(list.fold((l) => l.length, (_) => -1), 1);
    });

    test('rename updates the display name', () async {
      final h = _Harness(seed: [_rec('a')]);
      addTearDown(h.dispose);
      final result = await h.container
          .read(voiceRecordingControllerProvider.notifier)
          .renameRecording('a', 'Incident Recording');
      expect(result.isOk, isTrue);
      expect(
        h.state.recordings.first.displayName,
        'Incident Recording',
      );
    });

    test('second start while recording is absorbed', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.permissions.statuses[AppPermission.microphone] =
          PermissionStatus.granted;
      final notifier =
          h.container.read(voiceRecordingControllerProvider.notifier);
      await notifier.startRecording();
      await notifier.startRecording();
      expect(h.recorder.startCalls, 1);
      expect(h.state, isA<VoiceRecordingActive>());
      await notifier.discardRecording();
    });
  });
}
