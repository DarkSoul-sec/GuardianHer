import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/emergency_sms_bridge.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/providers.dart';
import '../../../features/contacts/application/contacts_providers.dart';
import '../../../features/contacts/domain/contacts_repository.dart';
import '../../../features/contacts/domain/trusted_contact.dart';
import '../../../features/location/application/location_controller.dart';
import '../../../features/location/application/location_providers.dart';
import '../../../features/location/application/location_state.dart';
import '../../../features/location/domain/location_point.dart';
import '../../../features/sos/application/sos_providers.dart';
import '../../../features/sos/application/sos_state.dart';
import '../../../features/sos/domain/sos_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State model
// ─────────────────────────────────────────────────────────────────────────────

/// High-level phase of the emergency orchestration.
enum EmergencyPhase {
  /// No emergency is active.
  idle,

  /// SOS activated; acquiring GPS, collecting data, dispatching SMS.
  active,

  /// Emergency ended; awaiting final cleanup.
  ending,

  /// Emergency fully ended.
  ended,
}

/// Delivery state of an individual guardian's emergency SMS.
enum GuardianDeliveryStatus {
  /// Not yet attempted.
  pending,

  /// Native service has accepted the send request.
  sending,

  /// SMS delivered by the modem.
  sent,

  /// Send failed (after all retries).
  failed,

  /// First attempt failed; native service is retrying.
  retrying,
}

/// Tracks one guardian's delivery through the emergency flow.
@immutable
class GuardianDelivery {
  const GuardianDelivery({
    required this.contactId,
    required this.contactName,
    this.status = GuardianDeliveryStatus.pending,
    this.error,
    this.sentAt,
  });

  final String contactId;
  final String contactName;
  final GuardianDeliveryStatus status;
  final String? error;
  final DateTime? sentAt;

  GuardianDelivery copyWith({
    GuardianDeliveryStatus? status,
    String? Function()? error,
    DateTime? sentAt,
  }) {
    return GuardianDelivery(
      contactId: contactId,
      contactName: contactName,
      status: status ?? this.status,
      error: error != null ? error() : this.error,
      sentAt: sentAt ?? this.sentAt,
    );
  }
}

/// Snapshot of the emergency orchestration state.
@immutable
class EmergencyOrchestratorState {
  const EmergencyOrchestratorState({
    this.phase = EmergencyPhase.idle,
    this.incidentId,
    this.startedAt,
    this.batteryPercentage,
    this.locationAcquired = false,
    this.locationUrl,
    this.locationStatusMessage,
    this.guardians = const [],
    this.errorMessage,
  });

  final EmergencyPhase phase;
  final String? incidentId;
  final DateTime? startedAt;
  final int? batteryPercentage;
  final bool locationAcquired;
  final String? locationUrl;
  final String? locationStatusMessage;
  final List<GuardianDelivery> guardians;
  final String? errorMessage;

  /// Duration since the emergency started, or zero if not started.
  Duration get elapsed {
    final start = startedAt;
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  /// Number of guardians whose SMS was sent successfully.
  int get sentCount =>
      guardians.where((g) => g.status == GuardianDeliveryStatus.sent).length;

  /// Number of guardians whose SMS failed (after all retries).
  int get failedCount =>
      guardians.where((g) => g.status == GuardianDeliveryStatus.failed).length;

  /// Whether all guardian SMS attempts are in a terminal state.
  bool get allGuardiansResolved => guardians.every(
        (g) =>
            g.status == GuardianDeliveryStatus.sent ||
            g.status == GuardianDeliveryStatus.failed,
      );

  EmergencyOrchestratorState copyWith({
    EmergencyPhase? phase,
    String? Function()? incidentId,
    DateTime? Function()? startedAt,
    int? Function()? batteryPercentage,
    bool? locationAcquired,
    String? Function()? locationUrl,
    String? Function()? locationStatusMessage,
    List<GuardianDelivery>? guardians,
    String? Function()? errorMessage,
  }) {
    return EmergencyOrchestratorState(
      phase: phase ?? this.phase,
      incidentId: incidentId != null ? incidentId() : this.incidentId,
      startedAt: startedAt != null ? startedAt() : this.startedAt,
      batteryPercentage:
          batteryPercentage != null ? batteryPercentage() : this.batteryPercentage,
      locationAcquired: locationAcquired ?? this.locationAcquired,
      locationUrl: locationUrl != null ? locationUrl() : this.locationUrl,
      locationStatusMessage:
          locationStatusMessage != null
              ? locationStatusMessage()
              : this.locationStatusMessage,
      guardians: guardians ?? this.guardians,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Orchestrator
// ─────────────────────────────────────────────────────────────────────────────

/// Central coordinator for the emergency SOS workflow.
///
/// Watches [sosControllerProvider] and orchestrates:
/// 1. GPS acquisition (non-blocking, ~45 s timeout to match location engine tiers)
/// 2. Battery collection
/// 3. Automatic SMS dispatch to all saved guardians via native foreground service
/// 4. Per-guardian delivery tracking (status streamed from native service)
/// 5. Post-SMS GPS retry with location-update SMS
///
/// The actual SMS sending is delegated to [NativeEmergencySmsBridge] — a
/// short-lived Android foreground service that survives MainActivity
/// destruction. This orchestrator only collects data, builds the SMS body,
/// and observes results.
///
/// App-rooted (watched from `GuardianHerApp.build()`): survives navigation
/// and keeps emergency state alive across screen transitions.
class EmergencyOrchestrator extends Notifier<EmergencyOrchestratorState> {
  /// Maximum time to wait for a GPS fix before sending SMS without location.
  /// Matches location engine: GPS tier (20s) + Network tier (15s) + buffer.
  static const Duration gpsTimeout = Duration(seconds: 45);

  NativeEmergencySmsBridge get _bridge => ref.read(nativeEmergencySmsBridgeProvider);
  ContactsRepository get _contacts => ref.read(contactsRepositoryProvider);
  LocationService get _locationService => ref.read(locationServiceProvider);

  Timer? _gpsTimeoutTimer;
  Timer? _safetyTimeout;
  StreamSubscription<EmergencySmsStatusUpdate>? _statusSub;
  StreamSubscription<EmergencySmsCompleteEvent>? _completeSub;
  bool _processing = false;
  List<TrustedContact> _contactsCache = [];

  @override
  EmergencyOrchestratorState build() {
    ref.onDispose(_cleanup);
    ref.listen(sosControllerProvider, _onSosStateChanged);
    return const EmergencyOrchestratorState();
  }

  /// Reacts to SOS state transitions.
  void _onSosStateChanged(SosState? previous, SosState next) {
    debugPrint('[EmergencySMS] SOS state changed: ${previous?.runtimeType} → ${next.runtimeType}, _processing=$_processing');
    switch (next) {
      case SosActive():
        if (previous is! SosActive && !_processing) {
          _startEmergency(next.event);
        }
      case SosCancelling():
      case SosCompleted():
        if (_processing) {
          _endEmergency();
        }
      case SosIdle():
        _reset();
      case SosCountdown():
        break;
    }
  }

  /// Begins the emergency workflow.
  Future<void> _startEmergency(SosEvent event) async {
    if (_processing) return;
    _processing = true;

    debugPrint('[EmergencySMS] Starting emergency workflow for event ${event.id.value}');

    try {
      // 1. Create incident state immediately.
      state = EmergencyOrchestratorState(
        phase: EmergencyPhase.active,
        incidentId: event.id.value,
        startedAt: DateTime.now(),
        guardians: const [],
      );

      // 2. Collect battery + start GPS concurrently.
      debugPrint('[EmergencySMS] Collecting battery + starting GPS...');
      final locationCtrl = ref.read(locationControllerProvider.notifier);
      final gpsFuture = _acquireLocationWithTimeout(locationCtrl);
      final batteryFuture = _getBattery();

      final battery = await batteryFuture;
      debugPrint('[EmergencySMS] Battery=$battery%');
      state = state.copyWith(batteryPercentage: () => battery);

      // 3. Wait for GPS (with timeout).
      final locationResult = await gpsFuture;
      final locationUrl = locationResult.url;
      final locationMessage = locationResult.message;
      final needsLocationSettings = locationResult.needsLocationSettings;

      debugPrint('[EmergencySMS] GPS result: url=$locationUrl, msg=$locationMessage, needsSettings=$needsLocationSettings');

      // If location services are disabled, open system settings and retry once.
      String? finalLocationUrl;
      String? finalLocationMessage;
      if (needsLocationSettings) {
        debugPrint('[EmergencySMS] GPS: opening location settings for user to enable...');
        state = state.copyWith(
          locationStatusMessage: () => 'Opening location settings...',
        );
        final opened = await _locationService.openLocationSettings();
        if (opened) {
          // Wait a moment for user to toggle, then retry capture.
          await Future<void>.delayed(const Duration(seconds: 2));
          debugPrint('[EmergencySMS] GPS: retrying capture after location settings...');
          await locationCtrl.captureLocation();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final retryState = ref.read(locationControllerProvider);
          debugPrint('[EmergencySMS] GPS retry: status=${retryState.status}, point=${retryState.point != null}');
          if (retryState.status == LocationStatus.captured && retryState.point != null) {
            final point = retryState.point!;
            finalLocationUrl = _buildLocationUrl(point);
            finalLocationMessage = 'Location captured after enabling';
          } else {
            finalLocationMessage = 'Location still unavailable after enabling attempt.';
          }
        } else {
          finalLocationMessage = 'Could not open location settings.';
        }
      } else if (locationUrl != null) {
        finalLocationUrl = locationUrl;
        finalLocationMessage = locationMessage;
      } else {
        finalLocationMessage = locationMessage;
      }

      if (finalLocationUrl != null) {
        state = state.copyWith(
          locationAcquired: true,
          locationUrl: () => finalLocationUrl,
          locationStatusMessage: () => finalLocationMessage,
        );
      } else {
        state = state.copyWith(
          locationStatusMessage: () => finalLocationMessage,
        );
      }

      // Bail out if the emergency was cancelled while GPS was being acquired.
      if (state.phase != EmergencyPhase.active) {
        debugPrint('[EmergencySMS] Phase changed during GPS — aborting');
        return;
      }

      // 4. Load contacts and build delivery list.
      debugPrint('[EmergencySMS] Loading contacts...');
      final contactsResult = await _contacts.loadContacts();
      final allContacts = contactsResult.fold(
        (list) => list,
        (_) => <TrustedContact>[],
      );
      
      // Only include emergency contacts
      final contacts = allContacts.where((c) => c.isEmergencyContact).toList();
      debugPrint('[EmergencySMS] Emergency contacts loaded: ${contacts.length} (of ${allContacts.length} total)');

      if (contacts.isEmpty) {
        state = state.copyWith(
          errorMessage: () => 'No emergency contacts configured. SMS not sent.',
          phase: EmergencyPhase.active,
        );
        debugPrint('[EmergencySMS] No emergency contacts — aborting');
        _processing = false;
        return;
      }

      _contactsCache = contacts;
      final deliveries = contacts
          .map(
            (c) => GuardianDelivery(
              contactId: c.id,
              contactName: c.name,
            ),
          )
          .toList();
      state = state.copyWith(guardians: deliveries);

      // 5. Request SEND_SMS runtime permission via native Android API
      //    (not permission_handler — too unreliable on OEM Android).
      debugPrint('[EmergencySMS] Checking SMS permission...');
      final hasPermission = await _bridge.checkSmsPermission();
      if (!hasPermission) {
        debugPrint('[EmergencySMS] SEND_SMS not granted, requesting via native API...');
        var granted = await _bridge.requestSmsPermission();
        // Retry once after a short delay — handles cold-start where Activity
        // isn't fully resumed yet when the first request fires.
        if (!granted) {
          debugPrint('[EmergencySMS] First request failed/denied, retrying in 1s...');
          await Future<void>.delayed(const Duration(seconds: 1));
          granted = await _bridge.requestSmsPermission();
        }
        if (!granted) {
          debugPrint('[EmergencySMS] SEND_SMS permission denied by user');
          state = state.copyWith(
            errorMessage: () => 'SMS permission denied. Emergency messages cannot be sent.',
          );
          _processing = false;
          return;
        }
        debugPrint('[EmergencySMS] SEND_SMS permission granted');
      }

      // 6. Build SMS body and delegate to native foreground service.
      final smsBody = _buildSmsBody(locationUrl, battery);
      debugPrint('[EmergencySMS] Delegating SMS to native service (${contacts.length} guardians)...');

      // Subscribe to native status/completion streams.
      _statusSub?.cancel();
      _completeSub?.cancel();
      _statusSub = _bridge.statusUpdates.listen(_onNativeStatusUpdate);
      _completeSub = _bridge.completionEvents.listen(_onNativeComplete);

      await _bridge.startEmergency(
        sosEventId: event.id.value,
        guardians: contacts.map((c) => EmergencyGuardianData(
          id: c.id,
          name: c.name,
          phoneNumber: c.phoneNumber,
        )).toList(),
        smsBody: smsBody,
        locationUrl: locationUrl,
        batteryPercentage: battery,
      );

      debugPrint('[EmergencySMS] Native service started — waiting for results');

      // Safety timeout: if the native service dies without notifying us
      // (e.g., OS kills it), force-complete after 4 minutes.
      _safetyTimeout?.cancel();
      _safetyTimeout = Timer(const Duration(minutes: 4), () {
        if (_processing && state.phase == EmergencyPhase.active) {
          debugPrint('[EmergencySMS] Safety timeout — force-completing');
          _processing = false;
          if (state.locationUrl == null) {
            _scheduleGpsRetry();
          }
        }
      });
    } catch (e, st) {
      debugPrint('[EmergencySMS] UNHANDLED ERROR: $e');
      debugPrint('[EmergencySMS] Stack trace: $st');
      _processing = false;
      state = state.copyWith(
        errorMessage: () => 'Emergency workflow error: $e',
      );
    }
  }

  /// Handles per-guardian status updates streamed from the native service.
  void _onNativeStatusUpdate(EmergencySmsStatusUpdate update) {
    if (state.phase != EmergencyPhase.active) return;

    debugPrint('[EmergencySMS] Native status: ${update.guardianId} → ${update.status} (error: ${update.error})');

    // System-level errors (permission denied, no SIM).
    if (update.guardianId == '_system') {
      state = state.copyWith(
        errorMessage: () => update.status == 'permission_denied'
            ? 'SMS permission denied. Emergency SMS not sent.'
            : 'No SIM card detected. Emergency SMS not sent.',
      );
      return;
    }

    // Find the guardian in the delivery list.
    final idx = state.guardians.indexWhere((g) => g.contactId == update.guardianId);
    if (idx < 0) return;

    final status = _mapNativeStatus(update.status);
    _updateDelivery(idx, status, error: update.error);
  }

  /// Handles the completion event from the native service.
  void _onNativeComplete(EmergencySmsCompleteEvent event) {
    debugPrint('[EmergencySMS] Native complete: sent=${event.totalSent} failed=${event.totalFailed}');
    _processing = false;
    _safetyTimeout?.cancel();

    // Schedule GPS retry if location was unavailable.
    if (state.locationUrl == null && state.phase == EmergencyPhase.active) {
      debugPrint('[EmergencySMS] Scheduling GPS retry...');
      _scheduleGpsRetry();
    }
  }

  /// Maps native status strings to [GuardianDeliveryStatus].
  GuardianDeliveryStatus _mapNativeStatus(String native) {
    return switch (native) {
      'sending' => GuardianDeliveryStatus.sending,
      'sent' => GuardianDeliveryStatus.sent,
      'retrying' => GuardianDeliveryStatus.retrying,
      'failed' => GuardianDeliveryStatus.failed,
      _ => GuardianDeliveryStatus.sending,
    };
  }

  /// Attempts GPS acquisition with a timeout. Never blocks the emergency flow.
  ///
  /// If location services are disabled, opens system settings for user to enable.
  /// Waits for user to return and retries once. If still disabled/unavailable,
  /// proceeds with SMS without location.
  Future<_LocationResult> _acquireLocationWithTimeout(
    LocationController locationCtrl,
  ) async {
    final completer = Completer<_LocationResult>();

    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer(gpsTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(
          const _LocationResult(
            message:
                'Location currently unavailable.\n'
                'Guardian HER is attempting to acquire the user\'s location.',
          ),
        );
      }
    });

    try {
      debugPrint('[EmergencySMS] GPS: calling captureLocation()...');
      await locationCtrl.captureLocation();

      // Give the location controller a moment to resolve.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final locState = ref.read(locationControllerProvider);

      debugPrint('[EmergencySMS] GPS: status=${locState.status}, point=${locState.point != null}');

      if (!completer.isCompleted) {
        if (locState.status == LocationStatus.captured && locState.point != null) {
          _gpsTimeoutTimer?.cancel();
          final point = locState.point!;
          completer.complete(
            _LocationResult(
              url: _buildLocationUrl(point),
              message: 'Location captured',
            ),
          );
        } else if (locState.status == LocationStatus.servicesDisabled && locState.openLocationSettings) {
          // Location services OFF — request user to enable via system dialog.
          debugPrint('[EmergencySMS] GPS: location services disabled, opening system settings...');
          _gpsTimeoutTimer?.cancel();
          completer.complete(
            _LocationResult(
              needsLocationSettings: true,
              message:
                  'Location is turned off. Opening settings to enable...',
            ),
          );
        } else {
          _gpsTimeoutTimer?.cancel();
          completer.complete(
            const _LocationResult(
              message:
                  'Location currently unavailable.\n'
                  'Guardian HER is attempting to acquire the user\'s location.',
            ),
          );
        }
      }
    } catch (_) {
      if (!completer.isCompleted) {
        _gpsTimeoutTimer?.cancel();
        completer.complete(
          const _LocationResult(
            message:
                'Location currently unavailable.\n'
                'Guardian HER is attempting to acquire the user\'s location.',
          ),
        );
      }
    }

    return completer.future;
  }

  /// Updates a single guardian's delivery status in the state list.
  void _updateDelivery(
    int index,
    GuardianDeliveryStatus status, {
    String? error,
    DateTime? sentAt,
  }) {
    final guardians = List<GuardianDelivery>.from(state.guardians);
    if (index >= guardians.length) return;
    guardians[index] = guardians[index].copyWith(
      status: status,
      error: () => error,
      sentAt: sentAt,
    );
    state = state.copyWith(guardians: guardians);
  }

  /// Schedules a second GPS attempt after initial SMS. If it succeeds,
  /// sends a location-update SMS to all guardians via the native service.
  void _scheduleGpsRetry() {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer(const Duration(seconds: 10), () async {
      if (state.phase != EmergencyPhase.active) return;

      try {
        final locationCtrl = ref.read(locationControllerProvider.notifier);
        await locationCtrl.captureLocation();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final locState = ref.read(locationControllerProvider);

        if (locState.status == LocationStatus.captured &&
            locState.point != null &&
            state.phase == EmergencyPhase.active) {
          final url = _buildLocationUrl(locState.point!);
          state = state.copyWith(
            locationAcquired: true,
            locationUrl: () => url,
            locationStatusMessage: () => 'Location updated',
          );

          // Send location-update SMS via the native service.
          final body = _buildLocationUpdateBody(url, state.batteryPercentage);
          debugPrint('[EmergencySMS] Sending location update via native service');
          await _bridge.startEmergency(
            sosEventId: state.incidentId ?? '',
            guardians: _contactsCache.map((c) => EmergencyGuardianData(
              id: c.id,
              name: c.name,
              phoneNumber: c.phoneNumber,
            )).toList(),
            smsBody: body,
            locationUrl: url,
            batteryPercentage: state.batteryPercentage,
          );
        }
      } catch (_) {
        // Best-effort; the initial SMS was already sent.
      }
    });
  }

  /// Builds the Google Maps URL for a location point.
  String _buildLocationUrl(LocationPoint point) {
    return 'https://maps.google.com/?q=${point.latitude},${point.longitude}';
  }

  /// Builds the emergency SMS body.
  String _buildSmsBody(String? locationUrl, int? battery) {
    final buffer = StringBuffer(
      '🚨 GUARDIAN HER — SOS ALERT\n\n'
      'An emergency SOS has been triggered.\n\n',
    );

    if (locationUrl != null) {
      buffer
        ..write('📍 Location:\n')
        ..write('$locationUrl\n\n');
    } else {
      buffer
        ..write('📍 Location currently unavailable.\n')
        ..write(
          'Guardian HER is attempting to acquire the user\'s location.\n\n',
        );
    }

    if (battery != null) {
      buffer.write('🔋 Battery: $battery%\n');
    }

    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    buffer
      ..write('🕐 Time: $hh:$mm\n\n')
      ..write('Please contact the user immediately.');

    return buffer.toString();
  }

  /// Builds a follow-up SMS with updated location.
  String _buildLocationUpdateBody(String locationUrl, int? battery) {
    final buffer = StringBuffer(
      '🚨 GUARDIAN HER — LOCATION UPDATE\n\n'
      'The user\'s location has been acquired:\n\n'
      '📍 Location:\n'
      '$locationUrl\n\n',
    );

    if (battery != null) {
      buffer.write('🔋 Battery: $battery%\n');
    }

    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    buffer
      ..write('🕐 Time: $hh:$mm\n\n')
      ..write('Please contact the user immediately.');

    return buffer.toString();
  }

  /// Best-effort battery percentage read via the native bridge.
  Future<int?> _getBattery() async {
    try {
      return await _bridge.getBatteryPercentage();
    } catch (_) {
      return null;
    }
  }

  /// Ends the emergency workflow when SOS is cancelled or completed.
  void _endEmergency() {
    _gpsTimeoutTimer?.cancel();
    _safetyTimeout?.cancel();
    _statusSub?.cancel();
    _completeSub?.cancel();
    _processing = false;

    // Cancel native service best-effort.
    _bridge.cancelEmergency();

    state = state.copyWith(phase: EmergencyPhase.ended);
  }

  /// Resets to idle for the next session.
  void _reset() {
    _gpsTimeoutTimer?.cancel();
    _safetyTimeout?.cancel();
    _statusSub?.cancel();
    _completeSub?.cancel();
    _processing = false;
    _contactsCache = [];
    state = const EmergencyOrchestratorState();
  }

  /// Cancels pending timers on disposal.
  void _cleanup() {
    _gpsTimeoutTimer?.cancel();
    _safetyTimeout?.cancel();
    _statusSub?.cancel();
    _completeSub?.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

class _LocationResult {
  const _LocationResult({
    this.url,
    required this.message,
    this.needsLocationSettings = false,
  });
  final String? url;
  final String? message;
  final bool needsLocationSettings;
}
