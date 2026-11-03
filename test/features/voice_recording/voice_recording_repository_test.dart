import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/voice_recording/data/voice_recording_repository_impl.dart';
import 'package:guardianher/features/voice_recording/domain/voice_recording.dart';

void main() {
  group('FileVoiceRecordingRepository', () {
    test('round trip preserves metadata newest-first', () async {
      final dir = await Directory.systemTemp.createTemp('voice_repo_test');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileVoiceRecordingRepository(directory: dir);

      final older = File('${dir.path}/voice_recordings/old.m4a')
        ..createSync(recursive: true);
      final newer = File('${dir.path}/voice_recordings/new.m4a')
        ..createSync(recursive: true);
      await repo.save(VoiceRecording(
        id: 'old',
        path: older.path,
        createdAt: DateTime.utc(2026, 9, 4, 12),
        duration: const Duration(seconds: 10),
        displayName: 'Recording - old',
      ));
      await repo.save(VoiceRecording(
        id: 'new',
        path: newer.path,
        createdAt: DateTime.utc(2026, 9, 4, 13),
        duration: const Duration(seconds: 20),
        displayName: 'Recording - new',
      ));

      final loaded = await repo.loadAll();
      expect(loaded.isOk, isTrue);
      expect(
        loaded.fold((l) => l.map((r) => r.id).toList(), (_) => <String>[]),
        ['new', 'old'],
      );
    });

    test('delete removes file and metadata without orphans', () async {
      final dir = await Directory.systemTemp.createTemp('voice_repo_del');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileVoiceRecordingRepository(directory: dir);
      final file = File('${dir.path}/voice_recordings/a.m4a')
        ..createSync(recursive: true);
      await repo.save(VoiceRecording(
        id: 'a',
        path: file.path,
        createdAt: DateTime.utc(2026, 9, 4, 12),
        duration: const Duration(seconds: 5),
        displayName: 'Recording - a',
      ));

      final result = await repo.delete('a');
      expect(result.isOk, isTrue);
      expect(await file.exists(), isFalse);
      final loaded = await repo.loadAll();
      expect(loaded.fold((l) => l, (_) => null), isEmpty);
    });

    test('deleteAll wipes files and index', () async {
      final dir = await Directory.systemTemp.createTemp('voice_repo_all');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileVoiceRecordingRepository(directory: dir);
      for (final id in ['a', 'b']) {
        final file = File('${dir.path}/voice_recordings/$id.m4a')
          ..createSync(recursive: true);
        await repo.save(VoiceRecording(
          id: id,
          path: file.path,
          createdAt: DateTime.utc(2026, 9, 4, 12),
          duration: const Duration(seconds: 5),
          displayName: 'Recording - $id',
        ));
      }

      final result = await repo.deleteAll();
      expect(result.isOk, isTrue);
      final loaded = await repo.loadAll();
      expect(loaded.fold((l) => l, (_) => null), isEmpty);
    });

    test('corrupt index degrades to empty, never crashes', () async {
      final dir = await Directory.systemTemp.createTemp('voice_repo_bad');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileVoiceRecordingRepository(directory: dir);
      await repo.loadAll(); // creates the directory
      await File('${dir.path}/voice_recordings/index.json')
          .writeAsString('not-json{{{');

      final loaded = await repo.loadAll();
      expect(loaded.isOk, isTrue);
      expect(loaded.fold((l) => l, (_) => null), isEmpty);
    });
  });
}
