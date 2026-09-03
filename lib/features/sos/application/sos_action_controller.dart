import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/platform/call_service.dart';
import '../../../core/platform/direct_sms_service.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/platform/notification_service.dart';
import '../../../core/platform/shake_sos_service.dart';
import '../../../core/platform/sms_service.dart';
import '../../../core/platform/sos_location_service.dart';
import '../../../core/platform/vibration_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/domain/phone_number.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../location/domain/location_share_message.dart';
import '../data/datasources/whatsapp_datasource_provider.dart';
import '../domain/sos_failures.dart';
import 'sos_actions_state.dart';
import 'sos_location_session_store.dart';
import 'sos_providers.dart';
import 'sos_state.dart';
import 'sos_tile_state.dart';

/// Coordinates SOS side effects without touching [SosController] or the
/// [SosStateMachine].
///
/// It listens to [sosControllerProvider] and maps state transitions to
/// platform effects:
///
/// * arming (countdown) → requests notification permission, once, in context;
/// * activation → starts the bounded one-shot SOS vibration and shows the
///   generic SOS notification (best-effort: a failure only marks status, it
///   never affects the SOS state machine);
/// * cancelling → stops the vibration and swaps the notification to "stopping";
/// * completed / idle → removes the notification (idempotent).
///
/// Emergency actions (calling a contact, composing a message, calling the
/// emergency number) are only ever user-triggered; nothing is sent
/// automatically. Outcomes describe what actually happened (e.g. "Dialer
/// opened.") — never "call completed" or "message sent".
class SosActionController extends Notifier<SosActionsState> {
  bool _requestedPermission = false;

  bool _nativeAlertEngaged = false;

  Timer? _locationRetryTimer;

  NotificationService get _notification =>
      ref.read(notificationServiceProvider);
  VibrationService get _vibration => ref.read(vibrationServiceProvider);
  CallService get _call => ref.read(callServiceProvider);
  SmsService get _sms => ref.read(smsServiceProvider);
  DirectSmsService get _directSms => ref.read(directSmsServiceProvider);
  WhatsAppDataSource get _whatsAppDataSource => ref.read(whatsAppDataSourceProvider);
  ContactsRepository get _contactsRepository =>
      ref.read(contactsRepositoryProvider);
  ShakeSosService get _shake => ref.read(shakeSosServiceProvider);
  SosLocationService get _sosLocation => ref.read(sosLocationServiceProvider);
  LocationService get _location => ref.read(locationServiceProvider);

  @override
  SosActionsState build() {
    ref.onDispose(() => _locationRetryTimer?.cancel());
    ref.listen(sosControllerProvider, (previous, next) {
      onSosStateChanged(previous, next);
    });
    // Sync the QS tile mirror to the AUTHORITATIVE current state right away
    // (Phase B). If the previous session died mid-SOS (force-stop, crash), the
    // persisted tile flag would otherwise stay "engaged" and the tile would
    // show a lie until the next full SOS cycle corrects it. This controller is
    // app-rooted (watched from GuardianHerApp), so every engine start — cold
    // boot included — re-anchors the mirror before any trigger can arm.
    unawaited(
      pushSosTileState(
        ref.read(sosTileStateServiceProvider),
        ref.read(sosControllerProvider),
      ),
    );
    // Write-through snapshot of the session's location knowledge (Phase 3I):
    // every location change while SOS is active updates the coordinate-free
    // persisted record; the record is dropped as soon as no active session.
    ref.listen(locationControllerProvider, (previous, next) {
      _persistLocationSnapshot(next);
    });
    return const SosActionsState();
  }

  /// Whether a snapshot for the CURRENT session has been written. Guards both
  /// duplicate writes and redundant clears.
  bool _sessionSnapshotActive = false;

  /// Persists [location] against the active session id — never coordinates,
  /// only state, capture time, accuracy and failure category. Fire-and-forget:
  /// a storage failure must never touch the SOS flow.
  void _persistLocationSnapshot(LocationState location) {
    final sos = ref.read(sosControllerProvider);
    if (sos is! SosActive) {
      if (_sessionSnapshotActive) {
        _sessionSnapshotActive = false;
        unawaited(_clearSessionSnapshot());
      }
      return;
    }
    final point = location.point;
    final sessionState = locationSessionStateOf(location);
    final record = SosLocationSessionRecord(
      sessionId: sos.event.id.value,
      state: sessionState.name,
      capturedAtEpochMs:
          point?.capturedAt.millisecondsSinceEpoch,
      accuracyMeters: point?.accuracyMeters,
      failureCategory: switch (location.status) {
        LocationStatus.servicesDisabled => 'servicesDisabled',
        LocationStatus.denied => 'permissionDenied',
        LocationStatus.timeout => 'timeout',
        LocationStatus.unavailable => 'unavailable',
        _ => null,
      },
    );
    _sessionSnapshotActive = true;
    unawaited(
      ref.read(sosLocationSessionStoreProvider).write(record),
    );
  }

  Future<void> _clearSessionSnapshot() async {
    try {
      await ref.read(sosLocationSessionStoreProvider).clear();
    } on Exception {
      // Best-effort hygiene; nothing in SOS depends on this succeeding.
    }
  }

  /// Reacts to an SOS state transition and triggers the matching effects.
  ///
  /// Public so tests can drive effect orchestration directly.
  Future<void> onSosStateChanged(SosState? previous, SosState next) async {
    // Mirror the state onto the Quick Settings SOS tile (Phase B). Pure
    // trigger surface: the tile never decides anything, it only reflects the
    // authoritative Dart-side SOS state. Fire-and-forget.
    unawaited(pushSosTileState(ref.read(sosTileStateServiceProvider), next));
    switch (next) {
      case SosCountdown():
        await _requestPermission();
      case SosActive():
        // Guard against re-activation while already active.
        if (previous is! SosActive) {
          await _activateEffects();
        }
      case SosCancelling():
        await _cancellingEffects();
      case SosCompleted():
        await _completedEffects();
      case SosIdle():
        await _idleEffects();
    }
  }

  Future<void> _requestPermission() async {
    if (_requestedPermission) {
      return;
    }
    _requestedPermission = true;
    final result = await _notification.requestPermission();
    if (result is! Ok) {
      state = state.copyWith(
        notificationPermission: SosNotificationPermission.denied,
        notificationStatus: SosNotificationStatus.unavailable,
      );
      return;
    }
    final granted = await _notification.isPermissionGranted();
    state = state.copyWith(
      notificationPermission: granted is Ok<bool> && granted.value
          ? SosNotificationPermission.granted
          : SosNotificationPermission.denied,
      notificationStatus: granted is Ok<bool> && granted.value
          ? SosNotificationStatus.unknown
          : SosNotificationStatus.unavailable,
    );
  }

  Future<void> _activateEffects() async {
    // Best-effort current-location capture. It never blocks SOS activation
    // and can never cancel an active SOS: the flow resolves to "captured" or
    // "location unavailable" while SOS stays ACTIVE. Runs regardless of the
    // notification outcome below.
    unawaited(_captureLocationWithContext());

    await _startAlert();

    final permission = await _notification.isPermissionGranted();
    final granted = permission is Ok<bool> && permission.value;
    if (!granted) {
      state = state.copyWith(
        notificationPermission: SosNotificationPermission.denied,
        notificationStatus: SosNotificationStatus.unavailable,
      );
      return;
    }
    state = state.copyWith(
      notificationPermission: SosNotificationPermission.granted,
    );
    final shown = await _notification.showSosActive();
    state = state.copyWith(
      notificationStatus: shown.isOk
              ? SosNotificationStatus.active
              : SosNotificationStatus.unavailable,
    );
  }

  /// Starts the SOS alert so it keeps vibrating while SOS stays active.
  ///
  /// When the native shake detector is running (Shake SOS enabled), the alert
  /// is handed to the foreground service so it survives the app being closed
  /// or the process being killed. Otherwise the OS-level repeating vibration
  /// pattern runs — which keeps alerting with the screen off or the app
  /// backgrounded. Cancellation stops both paths.
  Future<void> _startAlert() async {
    if (_nativeAlertEngaged) {
      return;
    }
    if (isShakeSosSupported) {
      try {
        final engaged = await _shake.startSosAlert();
        if (engaged) {
          _nativeAlertEngaged = true;
          state = state.copyWith(vibrationStatus: SosVibrationStatus.active);
          return;
        }
      } on Exception {
        // A channel failure is not fatal; fall back to the OS-level pattern.
      }
    }
    final vibration = await _vibration.playSosAlert();
    state = state.copyWith(
      vibrationStatus: vibration.isOk
          ? SosVibrationStatus.active
          : SosVibrationStatus.failed,
    );
  }

  /// Stops the native alert loop (when engaged) and any in-flight vibration.
  /// Idempotent.
  Future<void> _stopAlert() async {
    if (_nativeAlertEngaged) {
      _nativeAlertEngaged = false;
      try {
        await _shake.stopSosAlert();
      } on Exception {
        // Best-effort; a channel failure must not break SOS cancellation.
      }
    }
    await _vibration.stop();
  }

  /// Captures the current location while holding the location foreground
  /// context. On Android this starts [SosLocationService] first: a location
  /// foreground service is what lets a one-shot fix run while the phone is
  /// locked, the screen is off, or the app is backgrounded (the shake trigger
  /// path). Never blocks SOS activation and never affects the state machine.
  Future<void> _captureLocationWithContext() async {
    await _startLocationContext();
    await _ensureLocationEnabled();
    await ref.read(locationControllerProvider.notifier).captureLocation();
    _scheduleLocationRetry();
  }

  /// Turns location services on when SOS needs them and they are off.
  ///
  /// Tries the silent native path first ([LocationService.enableLocationServices],
  /// only effective with a WRITE_SECURE_SETTINGS grant or device-owner status);
  /// when the platform refuses, it opens the system location settings so the
  /// user can flip the switch in one tap — the location controller resumes the
  /// capture when they return. Best-effort: never blocks SOS and never throws.
  Future<void> _ensureLocationEnabled() async {
    if (!isShakeSosSupported) {
      return;
    }
    try {
      if (await _location.isLocationServiceEnabled()) {
        return;
      }
    } on Exception {
      return;
    }
    try {
      if (await _location.enableLocationServices()) {
        return;
      }
      await ref.read(locationControllerProvider.notifier).openLocationSettings();
    } on Exception {
      // Best-effort; captureLocation reports the truthful state.
    }
  }

  /// Starts the location foreground service, best-effort. A failure (e.g.
  /// location permission missing) is not fatal — captureLocation then reports
  /// the truthful denied/unavailable state and the screen offers a recovery
  /// action.
  Future<void> _startLocationContext() async {
    if (!isShakeSosSupported) {
      return;
    }
    try {
      await _sosLocation.start();
    } on Exception {
      // Best-effort; the capture outcome still reflects reality.
    }
  }

  /// Stops the location foreground service and any pending retry. Idempotent.
  Future<void> _stopLocationContext() async {
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    if (!isShakeSosSupported) {
      return;
    }
    try {
      await _sosLocation.stop();
    } on Exception {
      // Best-effort; a channel failure must not break SOS cancellation.
    }
  }

  /// One automatic re-attempt of a capture that ended "unavailable",
  /// "timeout" or "services-disabled" while SOS stays active. The first fix
  /// after a locked-phone shake often just needs GPS time to settle, and a
  /// user being walked to the location switch needs a re-capture once they
  /// flip it. A single retry, gated on SOS still being active; never retries
  /// denied (that needs Settings + user action).
  void _scheduleLocationRetry() {
    final location = ref.read(locationControllerProvider);
    if (location.status != LocationStatus.unavailable &&
        location.status != LocationStatus.timeout &&
        location.status != LocationStatus.servicesDisabled) {
      return;
    }
    if (ref.read(sosControllerProvider) is! SosActive) {
      return;
    }
    _locationRetryTimer?.cancel();
    _locationRetryTimer = Timer(ref.read(sosLocationRetryDelayProvider), () {
      _locationRetryTimer = null;
      if (ref.read(sosControllerProvider) is SosActive) {
        unawaited(_retryLocationCapture());
      }
    });
  }

  /// Re-runs the location flow for a retry, re-attempting the auto-enable in
  /// case the user turned location on while the retry window was pending.
  Future<void> _retryLocationCapture() async {
    await _ensureLocationEnabled();
    await ref.read(locationControllerProvider.notifier).captureLocation();
  }

  Future<void> _cancellingEffects() async {
    await _stopAlert();
    await _stopLocationContext();
    state = state.copyWith(vibrationStatus: SosVibrationStatus.idle);
    await _notification.showSosStopping();
    state = state.copyWith(
      notificationStatus: SosNotificationStatus.stopping,
    );
    _sessionSnapshotActive = false;
    await _clearSessionSnapshot();
  }

  Future<void> _completedEffects() async {
    await _notification.cancelSos();
    state = state.copyWith(notificationStatus: SosNotificationStatus.unknown);
  }

  Future<void> _idleEffects() async {
    await _notification.cancelSos();
    await _stopAlert();
    await _stopLocationContext();
    _requestedPermission = false;
    _sessionSnapshotActive = false;
    await _clearSessionSnapshot();
    state = const SosActionsState();
    // A new SOS session starts fresh: discard any previous location capture.
    ref.read(locationControllerProvider.notifier).reset();
  }

  /// Opens the dialer for a trusted contact. Single, deliberate user action.
  Future<Result<SosActionOutcome>> callContact(TrustedContact contact) {
    return _callAction(
      SosActionKind.callContact,
      () => _call.openDialer(PhoneNumber.normalize(contact.phoneNumber)),
      contact,
    );
  }

  /// Opens the SMS composer for a trusted contact. Single, deliberate action.
  ///
  /// The body includes the captured location as a shareable link when the
  /// session obtained a fix (current-location sharing); the user reviews and
  /// sends it in the messaging app.
  Future<Result<SosActionOutcome>> messageContact(TrustedContact contact) {
    return _callAction(
      SosActionKind.messageContact,
      () => _sms.openComposer(
        phoneNumber: PhoneNumber.normalize(contact.phoneNumber),
        body: ref.read(sosMessageBodyProvider),
      ),
      contact,
    );
  }

  /// Opens the dialer for the emergency services number. User-controlled.
  ///
  /// Emergency numbers are short (e.g. 112), so they are not subject to the
  /// trusted-contact digit-count validation — any non-empty digits-only number
  /// is dialable.
  Future<Result<SosActionOutcome>> callEmergency() async {
    final number = PhoneNumber.normalize(
      ref.read(sosEmergencyNumberProvider),
    );
    if (number.isEmpty) {
      return const Err(InvalidSosContactFailure(
        message: 'The emergency number is not available.',
      ));
    }
    return _callAction(
      SosActionKind.callEmergency,
      () => _call.openDialer(number),
    );
  }

  /// Opens WhatsApp with pre-filled SOS message for all emergency contacts.
  ///
  /// User-mediated: the user chooses to send via WhatsApp from the SOS screen.
  /// Opens a single WhatsApp group or individual chats for emergency contacts.
  /// Returns success if at least one WhatsApp chat was opened.
  Future<Result<SosActionOutcome>> sendSosViaWhatsApp() async {
    return _callAction(
      SosActionKind.sendWhatsApp,
      () async {
        try {
          final contactsResult = await _contactsRepository.loadContacts();
          final contacts = contactsResult.fold(
            (list) => list,
            (_) => <TrustedContact>[],
          );

          if (contacts.isEmpty) {
            return const Err(InvalidSosContactFailure(
              message: 'No trusted contacts saved.',
            ));
          }

          // Only send to contacts marked as emergency contacts
          final emergencyContacts = contacts
              .where((c) => c.isEmergencyContact)
              .toList();

          if (emergencyContacts.isEmpty) {
            return const Err(InvalidSosContactFailure(
              message: 'No emergency contacts configured.',
            ));
          }

          String? locationUrl;
          int? batteryPercentage;

          // Get location URL from location controller
          final locationState = ref.read(locationControllerProvider);
          if (locationState.status == LocationStatus.captured &&
              locationState.point != null) {
            locationUrl = buildMapsShareUrl(locationState.point!);
          }

          // Get battery percentage
          try {
            batteryPercentage = await _directSms.getBatteryPercentage();
          } catch (_) {
            // Battery read is best-effort
          }

          // Build emergency message
          final message = _buildEmergencyMessage(
            locationUrl: locationUrl,
            batteryPercentage: batteryPercentage,
          );

          // Open WhatsApp for all emergency contacts
          final numbers = emergencyContacts
              .map((c) => PhoneNumber.normalize(c.phoneNumber))
              .where(PhoneNumber.isValid)
              .toList();

          final successCount = await _whatsAppDataSource.openWhatsAppForAllContacts(
            numbers: numbers,
            message: message,
          );

          if (successCount > 0) {
            return Ok(SosActionOutcome.success(
              SosActionKind.sendWhatsApp,
              'WhatsApp opened for $successCount/${numbers.length} contacts.',
            ));
          } else {
            return const Err(InvalidSosContactFailure(
              message: 'WhatsApp could not be opened.',
            ));
          }
        } catch (e) {
          debugPrint('[SOS] WhatsApp error: $e');
          return const Err(InvalidSosContactFailure(
            message: 'Failed to open WhatsApp.',
          ));
        }
      },
    );
  }

  /// Builds the emergency SMS/WhatsApp message body.
  String _buildEmergencyMessage({
    String? locationUrl,
    int? batteryPercentage,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🚨 GUARDIAN HER — SOS ALERT');
    buffer.writeln('');
    buffer.writeln('An emergency SOS has been triggered.');
    buffer.writeln('');

    if (locationUrl != null) {
      buffer.writeln('📍 Current Location:');
      buffer.writeln(locationUrl);
      buffer.writeln('');
    } else {
      buffer.writeln('📍 Location currently unavailable.');
      buffer.writeln('Guardian HER is attempting to acquire the location.');
      buffer.writeln('');
    }

    if (batteryPercentage != null) {
      buffer.writeln('🔋 Battery: $batteryPercentage%');
      buffer.writeln('');
    }

    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    buffer.writeln('🕐 Time: $hh:$mm');
    buffer.writeln('');
    buffer.writeln('Please contact the user immediately.');

    return buffer.toString();
  }

  Future<Result<SosActionOutcome>> _callAction(
    SosActionKind kind,
    Future<Result<void>> Function() operation, [
    TrustedContact? contact,
  ]) async {
    if (contact != null && !PhoneNumber.isValid(contact.phoneNumber)) {
      return const Err(InvalidSosContactFailure());
    }
    final result = await operation();
    final outcome = _toOutcome(kind, result);
    state = state.copyWith(lastOutcome: () => outcome);
    return Ok(outcome);
  }

  SosActionOutcome _toOutcome(SosActionKind kind, Result<void> result) {
    final message = switch (result) {
      Ok() => switch (kind) {
          SosActionKind.callContact => 'Dialer opened.',
          SosActionKind.messageContact => 'SMS composer opened.',
          SosActionKind.callEmergency => 'Dialer opened.',
          SosActionKind.sendWhatsApp => 'WhatsApp opened.',
        },
      Err(:final failure) => failure.message,
    };
    return result.isOk
        ? SosActionOutcome.success(kind, message)
        : SosActionOutcome.failure(kind, message);
  }
}