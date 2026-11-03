import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/voice_recording.dart';
import 'voice_recording_repository.dart';

/// File-backed [VoiceRecordingRepository].
///
/// Audio lives in `<documents>/voice_recordings/*.m4a`, metadata in
/// `index.json` beside them. Storage failures surface as [StorageFailure];
/// a corrupt index degrades to an empty list rather than crashing.
class FileVoiceRecordingRepository implements VoiceRecordingRepository {
  FileVoiceRecordingRepository({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  static const _subdir = 'voice_recordings';
  static const _indexName = 'index.json';

  Future<Directory> _dir() async {
    if (_directory != null) {
      final dir = Directory('${_directory.path}/$_subdir');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_subdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indexFile() async => File('${(await _dir()).path}/$_indexName');

  Future<List<VoiceRecording>> _readIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      final out = <VoiceRecording>[];
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final rec = VoiceRecording.tryFromJson(entry);
          if (rec != null) out.add(rec);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<VoiceRecording> recordings) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(recordings.map((r) => r.toJson()).toList()),
    );
  }

  List<VoiceRecording> _sorted(List<VoiceRecording> recordings) {
    final sorted = List<VoiceRecording>.of(recordings)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<Result<List<VoiceRecording>>> loadAll() async {
    try {
      return Ok(_sorted(await _readIndex()));
    } on Exception {
      return const Err(StorageFailure('Voice recordings could not be loaded.'));
    }
  }

  @override
  Future<Result<VoiceRecording>> save(VoiceRecording recording) async {
    try {
      if (!await File(recording.path).exists()) {
        return const Err(
            StorageFailure('The recording file is missing and was not saved.'));
      }
      final current = await _readIndex();
      current.removeWhere((r) => r.id == recording.id);
      current.add(recording);
      await _writeIndex(current);
      return Ok(recording);
    } on Exception {
      return const Err(StorageFailure('The recording could not be saved.'));
    }
  }

  @override
  Future<Result<VoiceRecording>> rename({
    required String id,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      return const Err(StorageFailure('The recording name cannot be empty.'));
    }
    try {
      final current = await _readIndex();
      final index = current.indexWhere((r) => r.id == id);
      if (index < 0) {
        return const Err(StorageFailure('The recording was not found.'));
      }
      final updated = VoiceRecording(
        id: current[index].id,
        path: current[index].path,
        createdAt: current[index].createdAt,
        duration: current[index].duration,
        displayName: name,
      );
      current[index] = updated;
      await _writeIndex(current);
      return Ok(updated);
    } on Exception {
      return const Err(StorageFailure('The recording could not be renamed.'));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      final current = await _readIndex();
      final index = current.indexWhere((r) => r.id == id);
      if (index < 0) return const Ok(null);
      try {
        final file = File(current[index].path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Missing/unreadable file must not block metadata cleanup.
      }
      current.removeAt(index);
      await _writeIndex(current);
      return const Ok(null);
    } on Exception {
      return const Err(StorageFailure('The recording could not be deleted.'));
    }
  }

  @override
  Future<Result<void>> deleteAll() async {
    try {
      final current = await _readIndex();
      for (final rec in current) {
        try {
          final file = File(rec.path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      try {
        final index = await _indexFile();
        if (await index.exists()) await index.delete();
      } catch (_) {}
      return const Ok(null);
    } on Exception {
      return const Err(StorageFailure('Voice recordings could not be deleted.'));
    }
  }

  @override
  Future<({String path, String displayName})> nextRecordingTarget({
    required DateTime now,
  }) async {
    final dir = await _dir();
    final stamp = now.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final displayName =
        'Recording - ${two(now.day)} ${_month(now.month)} ${now.year} '
        '${two(now.hour)}:${two(now.minute)}';
    final suffix = _randomSuffix();
    final path =
        '${dir.path}/rec_${stamp.millisecondsSinceEpoch}_$suffix.m4a';
    return (path: path, displayName: displayName);
  }

  static String _month(int month) => switch (month) {
        1 => 'Jan',
        2 => 'Feb',
        3 => 'Mar',
        4 => 'Apr',
        5 => 'May',
        6 => 'Jun',
        7 => 'Jul',
        8 => 'Aug',
        9 => 'Sep',
        10 => 'Oct',
        11 => 'Nov',
        _ => 'Dec',
      };

  static String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
