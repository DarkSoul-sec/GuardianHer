import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/platform/call_service.dart';
import 'package:guardianher/core/platform/direct_sms_service.dart';
import 'package:guardianher/core/platform/notification_service.dart';
import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/core/platform/sms_service.dart';
import 'package:guardianher/core/platform/vibration_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_timer.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';

import '../../helpers/fakes.dart';

/// A stable, valid event id used across SOS tests.
const testSosEventId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Manually-drivable [SosTimer] for deterministic controller tests.
///
/// Mirrors [TimerSosTimer] semantics: [start] synchronously emits the initial
/// [SosTimer.onTick], [tick] advances one second, and [fireComplete] fires the
/// pending completion callback.
class FakeSosTimer implements SosTimer {
  int startCalls = 0;
  int stopCalls = 0;
  Duration? startedDuration;
  int remaining = 0;
  void Function(int remainingSeconds)? _onTick;
  void Function()? _onComplete;

  @override
  bool get isRunning => _onTick != null;

  @override
  void start({
    required Duration duration,
    required void Function(int remainingSeconds) onTick,
    required void Function() onComplete,
  }) {
    startCalls++;
    startedDuration = duration;
    remaining = (duration.inMilliseconds / 1000).ceil();
    _onTick = onTick;
    _onComplete = onComplete;
    if (remaining <= 0) {
      fireComplete();
    } else {
      onTick(remaining);
    }
  }

  @override
  void stop() {
    stopCalls++;
    _onTick = null;
    _onComplete = null;
  }

  /// Simulates one second of the current countdown elapsing.
  void tick() {
    final onTick = _onTick;
    if (onTick == null) {
      return;
    }
    remaining -= 1;
    if (remaining <= 0) {
      fireComplete();
    } else {
      onTick(remaining);
    }
  }

  /// Fires the pending completion callback, if any, and clears the timer.
  void fireComplete() {
    final onComplete = _onComplete;
    _onTick = null;
    _onComplete = null;
    onComplete?.call();
  }
}

/// [VibrationService] fake recording invocations.
class FakeVibrationService implements VibrationService {
  bool hasVibratorResult = true;
  int playCalls = 0;
  int stopCalls = 0;
  Result<void>? playResult;

  @override
  Future<bool> hasVibrator() async => hasVibratorResult;

  @override
  Future<Result<void>> playSosAlert() async {
    playCalls++;
    return playResult ?? const Ok(null);
  }

  @override
  Future<Result<void>> stop() async {
    stopCalls++;
    return const Ok(null);
  }
}

/// [NotificationService] fake recording invocations.
class FakeNotificationService implements NotificationService {
  int permissionGrantedCalls = 0;
  int requestPermissionCalls = 0;
  int showActiveCalls = 0;
  int showStoppingCalls = 0;
  int cancelCalls = 0;
  Result<bool>? permissionResult;
  Result<void>? requestResult;
  Result<void>? showResult;

  @override
  Future<Result<bool>> isPermissionGranted() async {
    permissionGrantedCalls++;
    return permissionResult ?? const Ok(true);
  }

  @override
  Future<Result<void>> requestPermission() async {
    requestPermissionCalls++;
    return requestResult ?? const Ok(null);
  }

  @override
  Future<Result<void>> showSosActive() async {
    showActiveCalls++;
    return showResult ?? const Ok(null);
  }

  @override
  Future<Result<void>> showSosStopping() async {
    showStoppingCalls++;
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancelSos() async {
    cancelCalls++;
    return const Ok(null);
  }
}

/// [CallService] fake recording dialed numbers.
class FakeCallService implements CallService {
  final List<String> dialedNumbers = [];
  Result<void>? result;

  @override
  Future<Result<void>> openDialer(String phoneNumber) async {
    dialedNumbers.add(phoneNumber);
    return result ?? const Ok(null);
  }
}

/// [SmsService] fake recording composer invocations.
class FakeSmsService implements SmsService {
  final List<({String phoneNumber, String? body})> opened = [];
  Result<void>? result;

  @override
  Future<Result<void>> openComposer({
    required String phoneNumber,
    String? body,
  }) async {
    opened.add((phoneNumber: phoneNumber, body: body));
    return result ?? const Ok(null);
  }
}

/// [ShakeSosService] fake recording alert-loop delegation.
class FakeShakeSosService implements ShakeSosService {
  int startCalls = 0;
  int stopCalls = 0;
  bool startAlertResult = false;
  int startAlertCalls = 0;
  int stopAlertCalls = 0;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<String?> manufacturerToken() async => null;

  @override
  Future<bool> canDrawOverlays() async => true;

  @override
  Future<void> openOverlaySettings() async {}

  @override
  Future<bool> startSosAlert() async {
    startAlertCalls++;
    return startAlertResult;
  }

  @override
  Future<void> stopSosAlert() async => stopAlertCalls++;
}

/// Builds a container with every SOS dependency overridden for tests.
///
/// The real [TimerSosTimer] is replaced by a [FakeSosTimer] so tests control
/// time exactly. Platform services are replaced by recording fakes. Returns
/// the container and its fake timer together.
({ProviderContainer container, FakeSosTimer timer}) createSosContainer({
  DateTime? now,
  String eventId = testSosEventId,
  Duration countdownDuration = const Duration(seconds: 3),
  FakeVibrationService? vibration,
  FakeNotificationService? notification,
  FakeCallService? call,
  FakeSmsService? sms,
  FakeShakeSosService? shake,
  TestSosLocationService? sosLocation,
  FakeDirectSmsService? directSms,
  List<Override> extraOverrides = const [],
}) {
  final timer = FakeSosTimer();
  final container = createContainer(
    overrides: [
      sosTimerProvider.overrideWithValue(timer),
      sosClockProvider.overrideWithValue(() => now ?? DateTime(2026, 1, 1, 12)),
      sosEventIdGeneratorProvider.overrideWithValue(() => SosEventId(eventId)),
      sosCountdownDurationProvider.overrideWithValue(countdownDuration),
      vibrationServiceProvider.overrideWithValue(vibration ?? FakeVibrationService()),
      notificationServiceProvider.overrideWithValue(
        notification ?? FakeNotificationService(),
      ),
      callServiceProvider.overrideWithValue(call ?? FakeCallService()),
      smsServiceProvider.overrideWithValue(sms ?? FakeSmsService()),
      shakeSosServiceProvider.overrideWithValue(shake ?? FakeShakeSosService()),
      sosLocationServiceProvider.overrideWithValue(
        sosLocation ?? TestSosLocationService(),
      ),
      directSmsServiceProvider.overrideWithValue(directSms ?? FakeDirectSmsService()),
      ...extraOverrides,
    ],
  );
  return (container: container, timer: timer);
}
