import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/live_location_platform.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/providers.dart';
import '../../location/domain/location_point.dart';
import '../data/live_location_api_client.dart';
import '../domain/live_location_failures.dart';
import '../domain/live_location_session.dart';
import 'live_location_providers.dart';
import 'live_location_state.dart';

/// Drives the live-location lifecycle (Phase 3J §7):
///
///   start → [permission] → FGS start → engine stream → backend session
///         → upload loop (latest-fix-only) → expiry timer
///   stop  → engine stop → FGS stop → backend revoke (best-effort) → idle
///
/// Invariants:
/// - The session token lives ONLY in this controller's state, in memory.
/// - Offline: capture CONTINUES; the UI reports "Connection unavailable";
///   when connectivity returns only the LATEST fix is uploaded (§8).
/// - Expiry is enforced locally for UX and by the server for truth.
/// - [startEmergency] never throws and never blocks SOS activation (§18).
class LiveLocationController extends Notifier<LiveLocationState> {
  StreamSubscription<LiveFix>? _fixSub;
  Timer? _uploadTimer;
  Timer? _expiryTimer;

  /// Duration requested for the current session; reused if an offline start
  /// must create the backend session later.
  LiveShareDuration _intendedDuration = LiveShareDuration.minutes30;

  @override
  LiveLocationState build() => const LiveLocationState();

  bool get _hasSession =>
      state.status == LiveSessionStatus.active ||
      state.status == LiveSessionStatus.starting ||
      state.status == LiveSessionStatus.stopping;

  LiveLocationApiClient get _api => ref.read(liveLocationApiClientProvider);

  /// User-initiated share with the NORMAL cadence.
  Future<bool> start(LiveShareDuration duration) =>
      _startSession(duration, LiveUpdateInterval.normal);

  /// SOS emergency share: faster cadence, fire-and-forget safe. Returns the
  /// eventual outcome but NEVER throws; failures leave SOS untouched (§18).
  Future<bool> startEmergency() async {
    try {
      return await _startSession(
        ref.read(liveSosDurationProvider),
        LiveUpdateInterval.sos,
      );
    } catch (_) {
      // Absolute rule: a live-location problem can never affect SOS.
      return false;
    }
  }

  Future<bool> _startSession(
    LiveShareDuration duration,
    LiveUpdateInterval interval,
  ) async {
    if (_hasSession) return false;
    _intendedDuration = duration;

    if (!ref.read(liveLocationApiConfiguredProvider)) {
      state = const LiveLocationState(
        status: LiveSessionStatus.failed,
        failure: LiveLocationStateNotice('failedNotConfigured'),
      );
      return false;
    }

    state = const LiveLocationState(status: LiveSessionStatus.starting);

    final locationService = ref.read(locationServiceProvider);

    // Permission first: a refusal is a clean, honest failure — nothing was
    // started, nothing needs tearing down.
    var permission = await locationService.checkPermission();
    if (permission != PermissionStatus.granted) {
      permission = await locationService.requestPermission();
    }
    if (permission != PermissionStatus.granted) {
      state = const LiveLocationState(
        status: LiveSessionStatus.failed,
        failure: LiveLocationStateNotice('failedPermission'),
      );
      return false;
    }

    // Foreground service BEFORE the engine so continuous capture is legal
    // with the screen off / device locked (Android 10+ rules).
    try {
      await ref.read(liveLocationForegroundServiceProvider).start();
    } catch (_) {
      // Non-Android or channel trouble: continue foreground-only rather than
      // failing outright; the session may simply not survive screen-off.
    }

    // Native continuous updates (requestLocationUpdates on GPS+NETWORK).
    final Stream<LiveFix> fixes;
    try {
      fixes = await ref
          .read(liveLocationUpdatesProvider)
          .startUpdates(interval: interval.asDuration);
    } catch (_) {
      await _stopForegroundService();
      state = const LiveLocationState(
        status: LiveSessionStatus.failed,
        failure: LiveLocationStateNotice('failedServicesDisabled'),
      );
      return false;
    }

    // Backend session. Failure here does NOT abort the session: tracking
    // starts anyway and creation is retried on the next upload tick (§8).
    final created =
        await _api.createSession(duration: duration, interval: interval);
    final creation = created.getOrNull();
    final createdAt = ref.read(liveClockProvider)();
    final expiresAt =
        creation?.expiresAt ?? createdAt.add(duration.asDuration);

    final session = LiveLocationSession(
      sessionId: _newSessionId(),
      token: creation?.token ?? '',
      createdAt: createdAt,
      expiresAt: expiresAt,
      updateInterval: interval,
      shareUrl: creation?.shareUrl ?? '',
    );
    state = LiveLocationState(
      status: LiveSessionStatus.active,
      session: session,
      connectionUp: creation != null,
    );

    _listenFixes(fixes);
    _armUploadLoop(interval);
    _armExpiry(expiresAt);
    return true;
  }

  void _listenFixes(Stream<LiveFix> fixes) {
    _fixSub = fixes.listen(
      (fix) {
        final current = state.session;
        if (current == null || !state.isActive) return;
        final point = LocationPoint(
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMeters: fix.accuracyMeters,
          capturedAt:
              DateTime.fromMillisecondsSinceEpoch(fix.epochMs, isUtc: true),
        );
        if (!point.isValid) return;
        state = state.copyWith(
          lastPoint: point,
          session: current.copyWith(lastLocationAt: point.capturedAt),
        );
      },
      onError: (_) {
        // Engine hiccups are non-fatal: the next provider fix recovers.
      },
    );
  }

  /// Uploads THE latest captured fix every interval. No backlog, ever (§8).
  void _armUploadLoop(LiveUpdateInterval interval) {
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(interval.asDuration, (_) {
      unawaited(_uploadLatest());
    });
  }

  Future<void> _uploadLatest() async {
    final session = state.session;
    if (session == null || !state.isActive) return;

    if (session.token.isEmpty) {
      // Session creation still pending from an offline start: retry it first;
      // coordinates wait for the next tick rather than uploading to a dead URL.
      await _retryCreation();
      return;
    }
    final point = state.lastPoint;
    if (point == null) return; // nothing captured yet — honest silence

    final result = await _api.pushLocation(
      token: session.token,
      latitude: point.latitude,
      longitude: point.longitude,
      accuracyMeters: point.accuracyMeters,
      capturedAt: point.capturedAt,
    );
    if (session != state.session) return; // a newer lifecycle superseded us

    result.fold(
      (_) {
        if (!state.connectionUp) {
          state = state.copyWith(connectionUp: true);
        }
      },
      (failure) {
        if (failure is! LiveLocationFailure) return;
        switch (failure.type) {
          case LiveLocationFailureType.networkUnavailable:
          case LiveLocationFailureType.serverUnavailable:
          case LiveLocationFailureType.rejectedByServer:
            // Keep capturing; report truthfully and retry next tick.
            state = state.copyWith(connectionUp: false);
          case LiveLocationFailureType.sessionExpired:
            _finish(LiveSessionStatus.expired, 'expired');
          case LiveLocationFailureType.sessionRevoked:
            _finish(LiveSessionStatus.stopped, 'stoppedByUser');
          case LiveLocationFailureType.notConfigured:
          case LiveLocationFailureType.invalidResponse:
            break; // cannot happen mid-session; ignore defensively
        }
      },
    );
  }

  Future<void> _retryCreation() async {
    final session = state.session;
    if (session == null || !state.isActive) return;
    final created = await _api.createSession(
      duration: _intendedDuration,
      interval: session.updateInterval,
    );
    final creation = created.getOrNull();
    if (creation == null) return; // still offline; next tick tries again
    if (session != state.session) return;
    final renewed = LiveLocationSession(
      sessionId: session.sessionId,
      token: creation.token,
      createdAt: session.createdAt,
      expiresAt: creation.expiresAt,
      updateInterval: session.updateInterval,
      shareUrl: creation.shareUrl,
      lastLocationAt: session.lastLocationAt,
    );
    state = state.copyWith(session: renewed, connectionUp: true);
    _armExpiry(creation.expiresAt);
  }

  void _armExpiry(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final delay = expiresAt.difference(ref.read(liveClockProvider)());
    if (delay.isNegative) {
      _finish(LiveSessionStatus.expired, 'expired');
      return;
    }
    _expiryTimer = Timer(delay, () {
      _finish(LiveSessionStatus.expired, 'expired');
    });
  }

  /// User pressed STOP (§21): stop capture, stop service, revoke, purge.
  Future<void> stopSession() async {
    if (state.status != LiveSessionStatus.active) return;
    state = state.copyWith(status: LiveSessionStatus.stopping);
    final session = state.session;
    final token = session?.token ?? '';
    if (token.isNotEmpty) {
      // Best-effort revoke with purge; failure still ends local sharing and
      // the server TTL caps any orphaned session anyway.
      await _api.stopSession(token: token);
    }
    _finish(LiveSessionStatus.stopped, 'stoppedByUser');
  }

  /// Re-evaluates liveness when the UI resumes (§7 refreshSession).
  void refresh() {
    final session = state.session;
    if (session == null || !state.isActive) return;
    if (ref.read(liveClockProvider)().isAfter(session.expiresAt)) {
      _finish(LiveSessionStatus.expired, 'expired');
    }
  }

  /// Every terminal transition funnels through here so tracking can NEVER
  /// outlive the session: timers and the fix subscription are dropped and the
  /// engine + foreground service are stopped (device-verified invariant —
  /// a local TTL expiry that leaves the FGS running is an orphaned tracker).
  void _finish(LiveSessionStatus terminal, String noticeKey) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _fixSub?.cancel();
    _fixSub = null;
    unawaited(_teardownTracking());
    state = LiveLocationState(
      status: terminal,
      failure: LiveLocationStateNotice(noticeKey),
    );
  }

  Future<void> _teardownTracking() async {
    _fixSub?.cancel();
    _fixSub = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    try {
      await ref.read(liveLocationUpdatesProvider).stopUpdates();
    } catch (_) {
      // Never let teardown throw past the boundary.
    }
    await _stopForegroundService();
  }

  Future<void> _stopForegroundService() async {
    try {
      await ref.read(liveLocationForegroundServiceProvider).stop();
    } catch (_) {
      // Same policy as teardown above.
    }
  }

  String _newSessionId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      List.generate(8, (_) => Random.secure().nextInt(16).toRadixString(16))
          .join();
}
