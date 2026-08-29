import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/platform/preferences_service.dart';
import '../../location/application/location_state.dart';

/// Persisted snapshot of what the ACTIVE SOS session knows about location.
///
/// Purpose (Phase 3I): keep a small, coordinate-free record of the session's
/// location state so the UI can bridge gaps where Dart was not running when
/// the state changed (native shake path), and so a backgrounded/relaunched UI
/// can show what the session last knew instead of an empty line.
///
/// PRIVACY CONTRACT: the record stores ONLY
///
/// * the SOS session id,
/// * the coarse location state,
/// * the capture timestamp and platform-reported accuracy (when captured),
/// * the failure category (when failed).
///
/// Latitude/longitude, map URLs, contact data and message bodies are NEVER
/// written here, never logged by this class.
@immutable
final class SosLocationSessionRecord {
  const SosLocationSessionRecord({
    required this.sessionId,
    required this.state,
    this.capturedAtEpochMs,
    this.accuracyMeters,
    this.failureCategory,
  });

  final String sessionId;

  /// One of [SosLocationSessionState] names.
  final String state;

  /// UTC wall-clock epoch millis of the fix (captured/stale only).
  final int? capturedAtEpochMs;

  /// Platform-reported horizontal accuracy in meters (captured/stale only).
  final double? accuracyMeters;

  /// Coarse failure category (failed states only): `servicesDisabled`,
  /// `permissionDenied`, `timeout`, `unavailable`.
  final String? failureCategory;

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'state': state,
        if (capturedAtEpochMs != null)
          'capturedAtEpochMs': capturedAtEpochMs,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (failureCategory != null) 'failureCategory': failureCategory,
      };

  /// Defensive decode: anything off-spec returns null instead of trusting a
  /// corrupted record.
  static SosLocationSessionRecord? tryDecode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final sessionId = map['sessionId'];
      final state = map['state'];
      if (sessionId is! String || state is! String) return null;
      final capturedAt = map['capturedAtEpochMs'];
      final accuracy = map['accuracyMeters'];
      final category = map['failureCategory'];
      return SosLocationSessionRecord(
        sessionId: sessionId,
        state: state,
        capturedAtEpochMs: capturedAt is int ? capturedAt : null,
        accuracyMeters: accuracy is num ? accuracy.toDouble() : null,
        failureCategory: category is String ? category : null,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());
}

/// The seven truthful SOS location states persisted for the UI.
enum SosLocationSessionState {
  loading,
  captured,
  stale,
  servicesDisabled,
  permissionDenied,
  timeout,
  unavailable;
}

/// Maps a live [LocationState] onto the persisted coarse state. Staleness is
/// part of the state itself because "last known" must survive exactly.
SosLocationSessionState locationSessionStateOf(LocationState state) {
  final point = state.point;
  return switch (state.status) {
    LocationStatus.loading => SosLocationSessionState.loading,
    LocationStatus.captured when point != null && point.isStale =>
      SosLocationSessionState.stale,
    LocationStatus.captured => SosLocationSessionState.captured,
    LocationStatus.servicesDisabled =>
      SosLocationSessionState.servicesDisabled,
    LocationStatus.denied => SosLocationSessionState.permissionDenied,
    LocationStatus.timeout => SosLocationSessionState.timeout,
    LocationStatus.unavailable => SosLocationSessionState.unavailable,
    LocationStatus.idle => SosLocationSessionState.unavailable,
  };
}

/// Preferences-backed store for the active-session location snapshot.
///
/// One key, one record: the snapshot describes THE active session only and is
/// cleared when the session ends or at app boot if it survived a process
/// death (a dead session's leftovers must never look like live data).
class SosLocationSessionStore {
  SosLocationSessionStore(this._preferences);

  static const String storageKey = 'sos_location_session_v1';

  final PreferencesService _preferences;

  Future<void> write(SosLocationSessionRecord record) =>
      _preferences.setString(storageKey, record.encode());

  Future<SosLocationSessionRecord?> read() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return null;
    return SosLocationSessionRecord.tryDecode(raw);
  }

  Future<void> clear() => _preferences.remove(storageKey);
}
