import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../auth/application/app_lock_providers.dart';

/// Handles the "delete all local data" privacy action.
///
/// Exposes a busy flag ([state]) so the UI can show progress, then delegates
/// to the app-lock controller's destructive reset, which wipes all storage and
/// re-resolves the lock (returning the app to first launch).
class PrivacyController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<Result<void>> deleteAllLocalData() async {
    if (state) return const Ok<void>(null);
    state = true;
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .destructiveReset();
    state = false;
    return result;
  }
}