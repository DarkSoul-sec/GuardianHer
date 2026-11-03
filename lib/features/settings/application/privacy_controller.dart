import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../location/application/location_providers.dart';
import '../../safety_recorder/application/safety_recorder_controller.dart';
import '../../voice_recording/application/voice_recording_providers.dart';

/// Handles the "delete all local data" privacy action.
///
/// Exposes a busy flag ([state]) so the UI can show progress, then clears the
/// application's local data (trusted contacts, history, settings, safety
/// incidents) through [DataCleanupService], returning the app to its normal
/// empty/default state.
///
/// After persistent storage is wiped, in-memory provider state is also
/// invalidated so no stale data remains observable if the user stays in-app.
class PrivacyController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<Result<void>> deleteAllLocalData() async {
    if (state) return const Ok<void>(null);
    state = true;
    final result =
        await ref.read(dataCleanupServiceProvider).deleteAllLocalData();
    // Clear in-memory safety incidents (SharedPreferences was already wiped
    // by DataCleanupService, but the controller holds an in-memory copy).
    await ref.read(safetyRecorderProvider.notifier).clearAllIncidents();
    // Voice notes live in private app storage (outside secure storage and
    // preferences), so they need their own wipe; a leftover recording must
    // never survive a full data cleanup.
    await ref.read(voiceRecordingRepositoryProvider).deleteAll();
    ref.invalidate(voicePlaybackControllerProvider);
    // Invalidate providers that hold sensitive in-memory state so no stale
    // data remains observable if the user stays in the app after deletion.
    ref.invalidate(locationControllerProvider);
    ref.invalidate(contactsControllerProvider);
    state = false;
    return result;
  }
}