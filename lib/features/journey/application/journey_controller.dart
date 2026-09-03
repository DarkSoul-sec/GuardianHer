import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../safety_session/domain/safety_session_id.dart';
import '../../safety_session/domain/safety_session_machine.dart';
import '../../safety_session/domain/safety_session_status.dart';
import '../../safety_session/domain/safety_session_type.dart';
import '../../sos/application/sos_providers.dart';
import '../../sos/application/sos_state.dart';
import '../domain/journey_state.dart';
import '../domain/vehicle_registration.dart';
import 'emergency_vehicle_context.dart';

/// Drives the Safe Journey lifecycle (Phase C) on top of the shared
/// [SafetySessionMachine] (ledger, type `safeJourney`).
///
/// ESCALATION (shake during a journey): when SOS arms, this controller
/// TRANSFORMS the journey — it closes the journey's own share session and
/// lets the authoritative SOS pipeline run its emergency share.
///
/// The controller is APP-ROOTED (watched from GuardianHerApp), like the SOS
/// side-effect coordinator: escalation must work no matter which screen is
/// open when the phone shakes.
class JourneyController extends Notifier<JourneyState> {
  /// Set when this journey handed its vehicle context over to an active
  /// emergency: the context must then SURVIVE the journey until the SOS
  /// pipeline itself ends (requirement: no re-entry of the vehicle number).
  bool _vehicleHandedToSos = false;

  DateTime Function() get _clock => ref.read(sosClockProvider);

  @override
  JourneyState build() {
    // App-rooted escalation hook: a shake can arm SOS from anywhere (lock
    // screen tile, closed app, any screen). Registered on the SOS provider
    // itself so even an instant countdown→active cascade reaches us.
    ref.listen(sosControllerProvider, (_, next) {
      _onSosEngaged(next);
      _onSosSettled(next);
    });
    return const JourneyIdle();
  }

  /// Whether an emergency currently owns the device's safety flows.
  static bool _sosEngaged(SosState sos) =>
      sos is SosCountdown || sos is SosActive || sos is SosCancelling;

  /// Starts a journey. [vehicle] is optional and stays in memory only.
  ///
  /// Refused (honest notice, no state churn) while an emergency is active:
  /// SOS has absolute priority and the journey UI must never fight it.
  Future<void> startJourney({VehicleInfo? vehicle}) async {
    final sanitizedVehicle = _sanitize(vehicle);
    final sos = ref.read(sosControllerProvider);
    if (_sosEngaged(sos)) {
      state = const JourneyIdle(
        notice: 'An emergency is active. Journeys are paused until it ends.',
      );
      return;
    }
    if (state.isActiveLike) {
      return; // Duplicate start absorbed silently (state machine rule).
    }

    final ledger = SafetySessionMachine.start(
      null,
      type: SafetySessionType.safeJourney,
      id: SafetySessionId.generate(),
      now: _clock(),
    );
    final session = ledger.getOrNull();
    if (session == null) {
      state = const JourneyIdle(notice: 'Could not start the journey.');
      return;
    }
    state = JourneyStarting(session: session, vehicle: sanitizedVehicle);

    // Simulated share - no live tracking without live_location feature
    final started = true;
    if (!started) {
      _failStart();
      return;
    }
    final liveSession = _FakeLiveSession(
      sessionId: 'journey-${session.id.value}',
      shareUrl: 'https://guardianher.app/journey/${session.id.value}',
      expiresAt: _clock().add(const Duration(hours: 2)),
    );

    final activated = SafetySessionMachine.activate(session, now: _clock());
    final active = activated.getOrNull();
    if (active == null) {
      _failStart();
      return;
    }
    state = JourneyActive(
      session: active,
      vehicle: sanitizedVehicle,
      shareUrl: liveSession.shareUrl,
      expiresAt: liveSession.expiresAt,
      shareExpired: false,
    );
    _publishVehicleContext(sanitizedVehicle);
  }

  /// Defense in depth for the storage contract: whatever reaches the
  /// journey is stored CANONICAL ("DL01AB1234") and TRIMMED/clamped,
  /// regardless of caller. Registrations the normalizer cannot recognize
  /// are kept verbatim — never silently reshaped.
  VehicleInfo? _sanitize(VehicleInfo? vehicle) {
    if (vehicle == null) return null;
    var changed = false;

    String? clean(String? value) {
      final raw = value;
      if (raw == null || raw.isEmpty) return raw;
      final next = _clamp(raw.trim(), _maxOptionalFieldLength);
      if (next != raw) changed = true;
      return next;
    }

    var registration = vehicle.registrationNumber;
    final regRaw = registration;
    if (regRaw != null && regRaw.isNotEmpty) {
      final result = normalizeRegistration(regRaw);
      if (result is RegistrationValid) {
        registration = result.canonical;
        changed |= result.canonical != regRaw;
      }
    }

    final driver = clean(vehicle.driverName);
    final booking = clean(vehicle.bookingReference);

    if (!changed) return vehicle;
    return VehicleInfo(
      type: vehicle.type,
      registrationNumber: registration,
      driverName: driver,
      bookingReference: booking,
    );
  }

  static const int _maxOptionalFieldLength = 60;

  static String _clamp(String value, int maxLength) => value.length <= maxLength
      ? value
      : value.substring(0, maxLength);

  /// Vehicle context is the read-only bridge to the SOS screen during an
  /// escalation. A fresh journey always REPLACES it (never inherited from a
  /// previous journey) and null vehicle means an explicitly empty context.
  void _publishVehicleContext(VehicleInfo? vehicle) {
    ref.read(emergencyVehicleContextProvider.notifier).state = vehicle;
    _vehicleHandedToSos = false;
  }

  void _failStart() {
    state = JourneyIdle(
      notice: 'The journey could not start. Check location permission.',
    );
  }

  /// "Arrived": ends the journey and its share deliberately.
  Future<void> endJourney() async {
    final parts = switch (state) {
      JourneyActive(
          :final session,
          :final vehicle,
          :final shareUrl,
          :final expiresAt,
        ) =>
        (session, vehicle, shareUrl, expiresAt),
      JourneyStarting(:final session, :final vehicle) => (
          session,
          vehicle,
          '',
          _clock().add(const Duration(hours: 2)),
        ),
      _ => null,
    };
    if (parts == null) return;
    final (session, vehicle, shareUrl, expiresAt) = parts;

    final stopping = SafetySessionMachine.stop(session, now: _clock());
    final stoppedSession = stopping.getOrNull();
    if (stoppedSession != null) {
      state = JourneyActive(
        session: stoppedSession,
        vehicle: vehicle,
        shareUrl: shareUrl,
        expiresAt: expiresAt,
        shareExpired: true,
      );
    }
    final completed =
        SafetySessionMachine.complete(stoppedSession ?? session, now: _clock());
    state = JourneyCompleted(
      reason: JourneyEndReason.arrived,
      endedAt: completed.getOrNull()?.endedAt ?? _clock(),
      startedAt: session.startedAt,
      vehicle: vehicle,
    );
  }

  /// Shake/SOS during the journey: close OUR share, hand over to the
  /// authoritative SOS pipeline, record the transformation in the ledger.
  Future<void> _escalate(JourneyActive active) async {
    final stopping = SafetySessionMachine.stop(active.session, now: _clock());
    final completed = SafetySessionMachine.complete(
      stopping.getOrNull() ?? active.session,
      now: _clock(),
    );
    final endedAt = completed.getOrNull()?.endedAt ?? _clock();

    state = JourneyCompleted(
      reason: JourneyEndReason.escalatedToSos,
      endedAt: endedAt,
      startedAt: active.session.startedAt,
      vehicle: active.vehicle,
    );
    // Deliberately NOT clearing the vehicle context here: the emergency now
    // owns the story and must keep showing WHICH vehicle the user is in.
    _vehicleHandedToSos = true;
  }

  void _onSosEngaged(SosState sos) {
    if (!_sosEngaged(sos)) return;
    final current = state;
    if (current is JourneyActive) {
      unawaited(_escalate(current));
    } else if (current is JourneyStarting) {
      // Pre-flight still running: tear down whatever we began and close.
      unawaited(_escalateStarting(current));
    }
  }

  /// When the handed-over emergency settles (ended by the user), release the
  /// vehicle context: it belongs to the session, and the session is over.
  /// Both terminal shapes are covered because the SOS flow parks on
  /// [SosCompleted] before returning to idle.
  void _onSosSettled(SosState sos) {
    if (_vehicleHandedToSos && (sos is SosCompleted || sos is SosIdle)) {
      _vehicleHandedToSos = false;
      ref.read(emergencyVehicleContextProvider.notifier).state = null;
    }
  }

  Future<void> _escalateStarting(JourneyStarting starting) async {
    final completed = SafetySessionMachine.complete(
      starting.session.copyWith(status: SafetySessionStatus.stopping),
      now: _clock(),
    );
    state = JourneyCompleted(
      reason: JourneyEndReason.escalatedToSos,
      endedAt: completed.getOrNull()?.endedAt ?? _clock(),
      startedAt: starting.session.startedAt,
      vehicle: starting.vehicle,
    );
    // The context (if published) stays for the emergency; see _escalate.
    _vehicleHandedToSos = true;
  }

  /// Starts a FRESH share window for an ongoing journey after expiry
  /// (replaces the dead link; still exactly one live session).
  Future<void> shareAgain(JourneyActive active) async {
    if (_sosEngaged(ref.read(sosControllerProvider))) return;
    final liveSession = _FakeLiveSession(
      sessionId: 'journey-${active.session.id.value}-${DateTime.now().millisecondsSinceEpoch}',
      shareUrl: 'https://guardianher.app/journey/${active.session.id.value}/${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: _clock().add(const Duration(hours: 2)),
    );
    state = active.copyWith(
      shareUrl: liveSession.shareUrl,
      expiresAt: liveSession.expiresAt,
      shareExpired: false,
    );
  }

  /// Clears the terminal banner so Home can show a clean entry again. The
  /// vehicle context dies with it (arrived case) — nothing outlives the
  /// session.
  void dismissCompletion() {
    if (state is! JourneyCompleted) return;
    state = const JourneyIdle();
    if (!_vehicleHandedToSos &&
        !_sosEngaged(ref.read(sosControllerProvider))) {
      ref.read(emergencyVehicleContextProvider.notifier).state = null;
    }
  }
}

/// Minimal fake live session for journeys without live_location feature.
class _FakeLiveSession {
  const _FakeLiveSession({
    required this.sessionId,
    required this.shareUrl,
    required this.expiresAt,
  });

  final String sessionId;
  final String shareUrl;
  final DateTime expiresAt;
}