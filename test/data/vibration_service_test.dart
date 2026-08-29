import 'package:flutter_test/flutter_test.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart'
    as vpi;

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/data/vibration_service_impl.dart';

/// Replaces the real [vpi.VibrationPlatform] with an in-memory recorder so the
/// actual installed `vibration` package API can be exercised without hardware.
class RecordingVibrationPlatform extends vpi.VibrationPlatform {
  RecordingVibrationPlatform({this.hasVibratorResult = true});

  final bool hasVibratorResult;
  final List<({List<int> pattern, int repeat})> vibrateCalls = [];
  int cancelCalls = 0;

  @override
  Future<bool> hasVibrator() async => hasVibratorResult;

  @override
  Future<void> vibrate({
    int duration = 500,
    List<int> pattern = const [],
    int repeat = -1,
    List<int> intensities = const [],
    int amplitude = -1,
    double sharpness = 0.5,
  }) async {
    vibrateCalls.add((pattern: List<int>.from(pattern), repeat: repeat));
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

void main() {
  const service = VibrationServiceVibration();

  late RecordingVibrationPlatform platform;
  late vpi.VibrationPlatform original;

  setUp(() {
    original = vpi.VibrationPlatform.instance;
    platform = RecordingVibrationPlatform();
    vpi.VibrationPlatform.instance = platform;
  });

  tearDown(() {
    vpi.VibrationPlatform.instance = original;
  });

  group('VibrationServiceVibration', () {
    test('hasVibrator delegates to the platform', () async {
      expect(await service.hasVibrator(), isTrue);
    });

    test('playSosAlert vibrates with the repeating SOS pattern', () async {
      final result = await service.playSosAlert();

      expect(result, isA<Ok<void>>());
      expect(platform.vibrateCalls, hasLength(1));
      final call = platform.vibrateCalls.single;
      expect(call.pattern, sosVibrationPattern);
      // Loops from the start of the waveform so the alert repeats until stop.
      expect(call.repeat, sosVibrationRepeat);
      expect(call.repeat, 0);
    });

    test('playSosAlert reports unavailable when the device has no vibrator',
        () async {
      platform = RecordingVibrationPlatform(hasVibratorResult: false);
      vpi.VibrationPlatform.instance = platform;

      final result = await service.playSosAlert();

      expect(result, isA<Err<void>>());
      expect(result, isA<Err<void>>().having(
        (e) => e.failure,
        'failure',
        isA<VibrationUnavailableFailure>(),
      ));
      expect(platform.vibrateCalls, isEmpty);
    });

    test('stop cancels the platform vibration', () async {
      final result = await service.stop();

      expect(result, isA<Ok<void>>());
      expect(platform.cancelCalls, 1);
    });
  });

  group('repeating alert contract', () {
    test('the SOS pattern loops until stop() cancels it', () {
      expect(sosVibrationRepeat, 0);
      // Three short bursts (wait 0, vibrate 300, pause 200, vibrate 300,
      // pause 200, vibrate 300) followed by a 4 s quiet gap, then the cycle
      // repeats. The OS drives the loop so it alerts even while backgrounded.
      expect(sosVibrationPattern, [0, 300, 200, 300, 200, 300, 4000]);
    });
  });
}