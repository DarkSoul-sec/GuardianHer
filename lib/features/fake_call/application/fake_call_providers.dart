import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/local_notifications.dart';
import '../data/fake_call_alert_channel.dart';
import '../data/fake_call_notifier_impl.dart';
import '../domain/fake_call_alert.dart';
import '../domain/fake_call_state.dart';
import 'fake_call_controller.dart';

export '../domain/fake_call_config.dart';
export '../domain/fake_call_state.dart';
export 'fake_call_controller.dart';

/// Injected clock for fake-call timestamps (replace in tests).
final fakeCallClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Native system-ringtone + vibration alert seam.
final fakeCallAlertServiceProvider = Provider<FakeCallAlertService>(
  (ref) => const MethodChannelFakeCallAlert(),
);

/// Background fallback notification seam (shared plugin, no new permissions).
final fakeCallNotifierProvider = Provider<FakeCallNotifier>(
  (ref) => FakeCallLocalNotifier(
    plugin: ref.watch(flutterLocalNotificationsPluginProvider),
  ),
);

/// The fake-call lifecycle controller.
final fakeCallControllerProvider =
    NotifierProvider<FakeCallController, FakeCallState>(
  FakeCallController.new,
);
