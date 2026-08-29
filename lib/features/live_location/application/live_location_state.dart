import 'package:flutter/foundation.dart';

import '../../location/domain/location_point.dart';
import '../domain/live_location_session.dart';

/// Immutable UI state for the live-location feature.
///
/// PRIVACY: [lastPoint] lives in memory only, never in preferences or logs.
@immutable
class LiveLocationState {
  const LiveLocationState({
    this.status = LiveSessionStatus.idle,
    this.session,
    this.lastPoint,
    this.connectionUp = true,
    this.failure,
  });

  final LiveSessionStatus status;

  /// Present from `starting` until teardown completes; dropped afterwards so
  /// no token survives the session even in memory.
  final LiveLocationSession? session;

  /// Latest CAPTURED fix (may not yet be on the server).
  final LocationPoint? lastPoint;

  /// Whether the last upload (or session creation) succeeded. False while
  /// offline: capture continues locally and the UI says "Connection
  /// unavailable" instead of claiming sharing (§8).
  final bool connectionUp;

  /// Terminal failure explaining why status is failed/expired/stopped.
  final LiveLocationStateNotice? failure;

  bool get isActive => status == LiveSessionStatus.active;

  bool get isBusy =>
      status == LiveSessionStatus.starting || status == LiveSessionStatus.stopping;

  LiveLocationState copyWith({
    LiveSessionStatus? status,
    LiveLocationSession? session,
    LocationPoint? lastPoint,
    bool? connectionUp,
    LiveLocationStateNotice? failure,
    bool clearSession = false,
    bool clearFailure = false,
  }) {
    return LiveLocationState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      lastPoint: lastPoint ?? this.lastPoint,
      connectionUp: connectionUp ?? this.connectionUp,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// A terminal notice with a stable machine key for tests/copy mapping.
@immutable
class LiveLocationStateNotice {
  const LiveLocationStateNotice(this.key);

  /// e.g. stoppedByUser / expired / failedPermission / failedNotConfigured /
  /// failedNetwork.
  final String key;
}
