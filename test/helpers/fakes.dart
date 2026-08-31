import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/app_info_service.dart';
import 'package:guardianher/core/platform/device_admin_service.dart';
import 'package:guardianher/core/platform/direct_sms_service.dart';
import 'package:guardianher/core/platform/emergency_sms_bridge.dart';
import 'package:guardianher/core/platform/live_location_platform.dart';
import 'package:guardianher/core/platform/location_service.dart';
import 'package:guardianher/core/platform/map_service.dart';
import 'package:guardianher/core/platform/preferences_service.dart';
import 'package:guardianher/core/platform/share_service.dart';
import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/core/platform/sos_location_service.dart';
import 'package:guardianher/core/platform/sos_tile.dart';
import 'package:guardianher/core/platform/whatsapp_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/core/security/data_cleanup_service.dart';
import 'package:guardianher/core/security/secure_storage_service.dart';
import 'package:guardianher/features/check_in/domain/check_in_failures.dart';
import 'package:guardianher/features/check_in/domain/check_in_message.dart';
import 'package:guardianher/features/check_in/domain/check_in_message_sender.dart';
import 'package:guardianher/features/check_in/domain/check_in_scheduler.dart';
import 'package:guardianher/features/check_in/domain/check_in_settings.dart';
import 'package:guardianher/features/check_in/domain/check_in_settings_repository.dart';
import 'package:guardianher/features/live_location/application/live_location_providers.dart';
import 'package:guardianher/features/live_location/data/live_location_api_client.dart';
import 'package:guardianher/features/live_location/domain/live_location_session.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/domain/location_point.dart';

/// In-memory [SecureStorageService] for tests.
class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> clearAll() async => _values.clear();
}

/// In-memory [PreferencesService] for tests.
class FakePreferencesService implements PreferencesService {
  final Map<String, Object> _values = {};

  Set<String> getKeys() => _values.keys.toSet();

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<int?> getInt(String key) async => _values[key] as int?;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clearAll() async => _values.clear();
}

/// In-memory [DeviceAdminService] fake; activating/deactivating flips [active].
class FakeDeviceAdminService implements DeviceAdminService {
  bool active = false;
  int activationRequests = 0;
  int deactivations = 0;

  @override
  Future<bool> isActive() async => active;

  @override
  Future<bool> requestActivation() async {
    activationRequests++;
    active = true;
    return true;
  }

  @override
  Future<void> deactivate() async {
    deactivations++;
    active = false;
  }
}

/// Inert [ShakeSosService] fake: the native alert never engages, so SOS tests
/// drive the Flutter-side alert loop without touching the platform channel.
class TestShakeSosService implements ShakeSosService {
  int startCalls = 0;
  int stopCalls = 0;
  int startAlertCalls = 0;
  int stopAlertCalls = 0;
  bool startAlertResult = false;
  bool ignoringBatteryOptimizations = true;
  String? oemManufacturerToken;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<bool> isIgnoringBatteryOptimizations() async =>
      ignoringBatteryOptimizations;

  @override
  Future<String?> manufacturerToken() async => oemManufacturerToken;

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

/// Inert [SosLocationService] fake recording the location-context lifecycle so
/// SOS tests exercise it without touching the platform channel.
class TestSosLocationService implements SosLocationService {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> stop() async => stopCalls++;
}

/// Inert [SosTileStateService] fake recording the QS tile mirror (Phase B).
class TestSosTileStateService implements SosTileStateService {
  int setEngagedCalls = 0;
  bool? lastEngaged;

  @override
  Future<void> setEngaged({required bool engaged}) async {
    setEngagedCalls++;
    lastEngaged = engaged;
  }
}

/// [PermissionService] fake backed by a mutable status map.
class FakePermissionService implements PermissionService {
  final Map<AppPermission, PermissionStatus> statuses = {};
  int openSettingsCalls = 0;

  @override
  Future<PermissionStatus> status(AppPermission permission) async =>
      statuses[permission] ?? PermissionStatus.denied;

  @override
  Future<PermissionStatus> request(AppPermission permission) async =>
      statuses[permission] = PermissionStatus.granted;

  @override
  Future<void> openSettings() async {
    openSettingsCalls++;
  }
}

/// [AppInfoService] fake.
class FakeAppInfoService implements AppInfoService {
  @override
  Future<AppInfo> getAppInfo() async =>
      const AppInfo(appName: 'GuardianHer', version: '1.0.0', buildNumber: '1');
}

/// Configurable [DataCleanupService] fake.
class FakeDataCleanupService implements DataCleanupService {
  FakeDataCleanupService({this.result});

  final Result<void>? result;
  int calls = 0;

  @override
  Future<Result<void>> deleteAllLocalData() async {
    calls++;
    return result ?? const Ok<void>(null);
  }
}

/// Fixed location fix used by the location fakes.
final testLocationPoint = LocationPoint(
  latitude: 12.345678,
  longitude: 98.765432,
  accuracyMeters: 15,
  capturedAt: DateTime.utc(2026, 1, 1, 12),
);

/// [LocationService] fake with scriptable service/permission/fix results.
///
/// [permission] is the status returned by [checkPermission]; setting
/// [requestPermissionResult] grants a different status after the request (e.g.
/// `denied` -> `granted`). [point] and [failure] control the fix result, with
/// [point] winning when both are set.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.enabled = true,
    this.permission = PermissionStatus.granted,
    this.requestPermissionResult,
    this.point,
    this.failure,
  });

  bool enabled;
  PermissionStatus permission;
  PermissionStatus? requestPermissionResult;
  LocationPoint? point;
  LocationFailure? failure;
  bool openLocationSettingsResult = true;
  bool enableLocationServicesResult = false;

  int captureCount = 0;
  int permissionRequestCount = 0;
  int openLocationSettingsCount = 0;
  int enableLocationServicesCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<PermissionStatus> checkPermission() async => permission;

  @override
  Future<PermissionStatus> requestPermission() async {
    permissionRequestCount++;
    return requestPermissionResult ?? permission;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCount++;
    return openLocationSettingsResult;
  }

  @override
  Future<bool> enableLocationServices() async {
    enableLocationServicesCalls++;
    if (enableLocationServicesResult) {
      // Model reality: a successful silent enable leaves services on.
      enabled = true;
    }
    return enableLocationServicesResult;
  }

  @override
  Future<Result<LocationPoint>> getCurrentLocation() async {
    captureCount++;
    if (failure case final LocationFailure fail) return Err(fail);
    return Ok(point ?? testLocationPoint);
  }
}

/// [MapService] fake that records opened locations.
class FakeMapService implements MapService {
  FakeMapService({this.result});

  final Result<void>? result;
  int openCalls = 0;
  LocationPoint? lastOpened;

  @override
  Future<Result<void>> openLocation(LocationPoint point) async {
    openCalls++;
    lastOpened = point;
    return result ?? const Ok<void>(null);
  }
}

/// Core overrides wiring fakes for every core dependency. Individual
/// providers can still be re-overridden by later entries in [overrides].
List<Override> defaultOverrides({
  List<Override> overrides = const [],
}) {
  return [
    secureStorageServiceProvider.overrideWithValue(FakeSecureStorageService()),
    preferencesServiceProvider.overrideWithValue(FakePreferencesService()),
    permissionServiceProvider.overrideWithValue(FakePermissionService()),
    appInfoServiceProvider.overrideWithValue(FakeAppInfoService()),
    locationServiceProvider.overrideWithValue(FakeLocationService()),
    mapServiceProvider.overrideWithValue(FakeMapService()),
    shakeSosServiceProvider.overrideWithValue(TestShakeSosService()),
    sosLocationServiceProvider.overrideWithValue(TestSosLocationService()),
    // QS SOS tile mirror fake (Phase B): keeps every SOS-driving test off the
    // platform channel while still recording the mirrored state.
    sosTileStateServiceProvider.overrideWithValue(TestSosTileStateService()),
    whatsappServiceProvider.overrideWithValue(FakeWhatsAppService()),
    directSmsServiceProvider.overrideWithValue(FakeDirectSmsService()),
    nativeEmergencySmsBridgeProvider.overrideWithValue(FakeNativeEmergencySmsBridge()),
    // Live-location fakes (Phase 3J). The API fake is UNCONFIGURED by
    // default so any test that reaches the live flow fails fast without
    // touching channels; live-sharing tests override with a configured one.
    liveLocationForegroundServiceProvider
        .overrideWithValue(FakeLiveLocationForegroundService()),
    liveLocationUpdatesProvider.overrideWithValue(FakeLiveLocationUpdates()),
    liveLocationApiClientProvider
        .overrideWith((ref) => FakeLiveLocationApiClient()),
    ...overrides,
  ];
}

/// [LiveLocationForegroundService] fake counting start/stop transitions.
class FakeLiveLocationForegroundService
    implements LiveLocationForegroundService {
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

/// [LiveLocationUpdates] fake handing out a controllable fix stream.
///
/// Each [startUpdates] returns a FRESH single-subscription stream (matching
/// native EventChannel semantics), so a second session in the same container
/// works instead of throwing "already listened to". Controllers are swapped,
/// never closed: StreamController.close() never completes under fakeAsync and
/// would deadlock the awaited stop chain (device-parity regression guard).
class FakeLiveLocationUpdates implements LiveLocationUpdates {
  StreamController<LiveFix> _controller = StreamController<LiveFix>();

  int startCount = 0;
  int stopCount = 0;
  Duration? lastInterval;

  void emit(LiveFix fix) {
    _controller.add(fix);
  }

  @override
  Future<Stream<LiveFix>> startUpdates({required Duration interval}) async {
    startCount++;
    lastInterval = interval;
    return _controller.stream;
  }

  @override
  Future<void> stopUpdates() async {
    stopCount++;
    // Later starts must get a fresh stream; the abandoned controller has no
    // listeners or timers, so leaving it unclosed is inert.
    _controller = StreamController<LiveFix>();
  }
}

/// [LiveLocationApiClient] fake with scriptable results and a request log.
///
/// Starts UNCONFIGURED (matching an app built without GUARDIANHER_LIVE_API_URL)
/// so the feature is honestly dormant; set [configured] to exercise real flows.
class FakeLiveLocationApiClient implements LiveLocationApiClient {
  FakeLiveLocationApiClient({
    this.configured = false,
    this.creation,
    this.createResult,
    this.pushResults = const [],
    this.stopResult,
  });

  bool configured;
  LiveSessionCreation? creation;

  /// Scripts createSession outcomes; null means success using [creation].
  Result<LiveSessionCreation>? Function()? createResult;

  /// Scripts pushLocation outcomes per call, falling back to Ok.
  List<Result<void>> pushResults;
  int pushCalls = 0;
  Result<void>? stopResult;

  int createCalls = 0;
  int stopCalls = 0;
  final List<String> stoppedTokens = [];
  LiveUpdateInterval? lastCreateInterval;
  final List<({String token, double latitude, double longitude})> pushes = [];

  static LiveSessionCreation defaultCreation({
    LiveShareDuration duration = LiveShareDuration.minutes30,
  }) {
    return LiveSessionCreation(
      token: 'T' * 43,
      shareUrl: 'https://live.example.org/live/${'T' * 43}',
      expiresAt: DateTime.now().toUtc().add(duration.asDuration),
    );
  }

  @override
  bool get isConfigured => configured;

  @override
  Future<Result<LiveSessionCreation>> createSession({
    required LiveShareDuration duration,
    required LiveUpdateInterval interval,
  }) async {
    createCalls++;
    lastCreateInterval = interval;
    final scripted = createResult?.call();
    if (scripted != null) return scripted;
    return Ok(creation ?? defaultCreation(duration: duration));
  }

  @override
  Future<Result<void>> pushLocation({
    required String token,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
  }) async {
    pushes.add((token: token, latitude: latitude, longitude: longitude));
    final index = pushCalls;
    pushCalls++;
    if (index < pushResults.length) return pushResults[index];
    return const Ok(null);
  }

  @override
  Future<Result<void>> stopSession({required String token}) async {
    stopCalls++;
    stoppedTokens.add(token);
    return stopResult ?? const Ok(null);
  }
}

/// In-memory [CheckInSettingsRepository] for tests.
class FakeCheckInSettingsRepository implements CheckInSettingsRepository {
  FakeCheckInSettingsRepository([CheckInSettings? settings])
      : _settings = settings ?? CheckInSettings.initial;

  CheckInSettings _settings;
  CheckInSettings get saved => _settings;
  int saveCount = 0;

  @override
  Future<Result<CheckInSettings>> load() async => Ok(_settings);

  @override
  Future<Result<void>> save(CheckInSettings settings) async {
    _settings = settings;
    saveCount++;
    return const Ok(null);
  }
}

/// [CheckInScheduler] fake recording every scheduled/cancelled reminder.
class FakeCheckInScheduler implements CheckInScheduler {
  final List<({DateTime dueAt, int missedCount})> scheduled = [];
  final List<DateTime> executionsScheduled = [];
  int cancelCount = 0;
  bool failScheduling = false;

  @override
  Future<Result<void>> scheduleReminder(
    DateTime dueAt, {
    required int missedCount,
  }) async {
    if (failScheduling) {
      return const Err(CheckInSchedulingFailure());
    }
    scheduled.add((dueAt: dueAt, missedCount: missedCount));
    return const Ok(null);
  }

  @override
  Future<Result<void>> scheduleExecution(DateTime dueAt) async {
    if (failScheduling) {
      return const Err(CheckInSchedulingFailure());
    }
    executionsScheduled.add(dueAt);
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancelAll() async {
    cancelCount++;
    return const Ok(null);
  }
}

/// [CheckInMessageSender] fake capturing every handed-off message.
class FakeCheckInMessageSender implements CheckInMessageSender {
  final List<CheckInMessage> sent = [];
  bool failSending = false;

  @override
  Future<Result<void>> send(CheckInMessage message) async {
    if (failSending) {
      return const Err(CheckInSenderFailure());
    }
    sent.add(message);
    return const Ok(null);
  }
}

/// [ShareService] fake recording share-sheet invocations (Phase 3G).
class FakeShareService implements ShareService {
  final List<String> shared = [];
  Result<void>? result;

  @override
  Future<Result<void>> shareText(String text) async {
    shared.add(text);
    return result ?? const Ok(null);
  }
}

/// [WhatsAppService] fake recording chat-open attempts (Phase 3I).
///
/// [result] scripts the outcome; a failure never loops — each call performs
/// exactly one attempt.
class FakeWhatsAppService implements WhatsAppService {
  final List<({String phoneNumber, String? body})> opened = [];
  Result<void>? result;

  @override
  Future<Result<void>> openChat({
    required String phoneNumber,
    String? body,
  }) async {
    opened.add((phoneNumber: phoneNumber, body: body));
    return result ?? const Ok(null);
  }
}

/// [DirectSmsService] fake for testing the emergency orchestrator.
///
/// Records every send attempt; configurable via [simReady], [hasPermission],
/// [permissionResult], [sendResult] and [batteryPercentage].
class FakeDirectSmsService implements DirectSmsService {
  bool simReady = true;
  bool hasPermissionResult = true;
  bool? permissionResult;
  ({bool success, String? error})? sendResult;
  int? batteryPercentage;

  final List<({String phoneNumber, String body})> sent = [];
  int sendCalls = 0;
  int permissionRequestCalls = 0;

  @override
  Future<bool> checkSimReady() async => simReady;

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<bool> requestPermission() async {
    permissionRequestCalls++;
    return permissionResult ?? hasPermissionResult;
  }

  @override
  Future<({bool success, String? error})> sendSms({
    required String phoneNumber,
    required String body,
  }) async {
    sendCalls++;
    sent.add((phoneNumber: phoneNumber, body: body));
    return sendResult ?? (success: true, error: null);
  }

  @override
  Future<int?> getBatteryPercentage() async => batteryPercentage;
}

/// [NativeEmergencySmsBridge] fake for testing the emergency orchestrator.
///
/// Records start/cancel calls; configurable via [completionDelay].
/// Automatically emits completion after [startEmergency] unless
/// [autoComplete] is false.
class FakeNativeEmergencySmsBridge implements NativeEmergencySmsBridge {
  bool autoComplete = true;
  Duration completionDelay = Duration.zero;
  int? batteryPercentage;
  bool smsPermissionGranted = true;

  int startCalls = 0;
  int cancelCalls = 0;
  EmergencyGuardianData? lastStartGuardians;
  List<String> lastStartGuardianIds = const [];
  String? lastStartSmsBody;

  final _statusController = StreamController<EmergencySmsStatusUpdate>.broadcast();
  final _completionController = StreamController<EmergencySmsCompleteEvent>.broadcast();
  EmergencySmsCompleteEvent? lastCompletionEvent;

  @override
  Future<void> startEmergency({
    required String sosEventId,
    required List<EmergencyGuardianData> guardians,
    required String smsBody,
    String? locationUrl,
    int? batteryPercentage,
  }) async {
    startCalls++;
    lastStartGuardians = guardians.isNotEmpty ? guardians.first : null;
    lastStartGuardianIds = guardians.map((guardian) => guardian.id).toList();
    lastStartSmsBody = smsBody;

    // Emit per-guardian "sent" status.
    for (final g in guardians) {
      _statusController.add(EmergencySmsStatusUpdate(
        guardianId: g.id,
        status: 'sent',
      ));
    }

    // Auto-complete after delay (simulates native service finishing).
    if (autoComplete) {
      Future<void>.delayed(completionDelay, () {
        final event = EmergencySmsCompleteEvent(
          sosEventId: sosEventId,
          totalSent: guardians.length,
          totalFailed: 0,
        );
        lastCompletionEvent = event;
        _completionController.add(event);
      });
    }
  }

  @override
  Future<void> cancelEmergency() async {
    cancelCalls++;
  }

  @override
  Future<bool> checkSmsPermission() async => smsPermissionGranted;

  @override
  Future<bool> requestSmsPermission() async => smsPermissionGranted;

  @override
  Future<int?> getBatteryPercentage() async => batteryPercentage;

  @override
  Stream<EmergencySmsStatusUpdate> get statusUpdates => _statusController.stream;

  @override
  Stream<EmergencySmsCompleteEvent> get completionEvents => _completionController.stream;

  void dispose() {
    _statusController.close();
    _completionController.close();
  }
}

/// Builds a [ProviderContainer] pre-loaded with [defaultOverrides].
ProviderContainer createContainer({
  List<Override> overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      ...defaultOverrides(
        overrides: overrides,
      ),
    ],
  );
}
