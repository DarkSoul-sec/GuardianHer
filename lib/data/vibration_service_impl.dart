import 'package:vibration/vibration.dart' as v;

import '../core/error/failures.dart';
import '../core/platform/vibration_service.dart';
import '../core/result/result.dart';

/// Repeating SOS alert pattern in milliseconds: three short bursts (wait 0,
/// vibrate 300, pause 200, vibrate 300, pause 200, vibrate 300) followed by a
/// 4 s quiet gap, then the whole cycle starts again. The OS drives the loop, so
/// it keeps alerting while the screen is off or the app is backgrounded, and
/// `stop` cancels it.
const List<int> sosVibrationPattern = [0, 300, 200, 300, 200, 300, 4000];

/// Loop the waveform from its start (`0`) so the alert repeats until [stop].
const int sosVibrationRepeat = 0;

/// [VibrationService] backed by the `vibration` plugin.
///
/// The SOS alert repeats via the OS-level waveform loop ([sosVibrationRepeat]
/// is `0`): it keeps buzzing while SOS is active — including with the screen
/// off or the app backgrounded — and [stop] cancels it idempotently.
class VibrationServiceVibration implements VibrationService {
  const VibrationServiceVibration();

  @override
  Future<bool> hasVibrator() => v.Vibration.hasVibrator();

  @override
  Future<Result<void>> playSosAlert() async {
    try {
      if (!await v.Vibration.hasVibrator()) {
        return Err(VibrationUnavailableFailure());
      }
      await v.Vibration.vibrate(
        pattern: sosVibrationPattern,
        repeat: sosVibrationRepeat,
      );
      return const Ok(null);
    } catch (_) {
      return Err(VibrationUnavailableFailure());
    }
  }

  @override
  Future<Result<void>> stop() async {
    try {
      await v.Vibration.cancel();
      return const Ok(null);
    } catch (_) {
      return Err(VibrationUnavailableFailure());
    }
  }
}