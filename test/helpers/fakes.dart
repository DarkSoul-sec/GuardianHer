import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/app_info_service.dart';
import 'package:guardianher/core/platform/biometric_service.dart';
import 'package:guardianher/core/platform/preferences_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/core/security/data_cleanup_service.dart';
import 'package:guardianher/core/security/secure_storage_service.dart';
import 'package:guardianher/features/auth/application/app_lock_controller.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/application/app_lock_state.dart';
import 'package:guardianher/features/auth/application/pin_hasher.dart';
import 'package:guardianher/features/auth/domain/app_lock_status.dart';
import 'package:guardianher/features/auth/domain/credential_policy.dart';

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

/// Configurable [BiometricService] fake.
class FakeBiometricService implements BiometricService {
  FakeBiometricService({this.available = false, this.authenticateResult});

  bool available;
  Result<bool>? authenticateResult;
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Result<bool>> authenticate({required String reason}) async {
    authenticateCalls++;
    return authenticateResult ?? const Ok(true);
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

/// A fast [PinHasher] for tests (single iteration; verification still honors
/// the iteration count stored in the data).
class TestPinHasher extends PinHasher {
  TestPinHasher() : super(iterations: 1);
}

/// Core overrides wiring fakes for every Phase 1 dependency. Individual
/// providers can still be re-overridden by later entries in [overrides].
List<Override> defaultOverrides({
  bool biometricsAvailable = false,
  List<Override> overrides = const [],
}) {
  return [
    secureStorageServiceProvider.overrideWithValue(FakeSecureStorageService()),
    preferencesServiceProvider.overrideWithValue(FakePreferencesService()),
    biometricServiceProvider.overrideWithValue(
      FakeBiometricService(available: biometricsAvailable),
    ),
    permissionServiceProvider.overrideWithValue(FakePermissionService()),
    appInfoServiceProvider.overrideWithValue(FakeAppInfoService()),
    // Test hashes use 1 iteration for speed; the stored-credential policy is
    // relaxed so those credentials are still considered valid. Tests that
    // exercise the real policy override this explicitly.
    credentialPolicyProvider
        .overrideWithValue(const CredentialPolicy(minIterations: 1)),
    ...overrides,
  ];
}

/// Builds a [ProviderContainer] pre-loaded with [defaultOverrides].
ProviderContainer createContainer({
  bool biometricsAvailable = false,
  List<Override> overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      ...defaultOverrides(
        biometricsAvailable: biometricsAvailable,
        overrides: overrides,
      ),
    ],
  );
}

/// A controller that starts already unlocked. Used by widget tests that render
/// unlocked UI (e.g. the app shell) without a real lock setup.
class UnlockedAppLockController extends AppLockController {
  @override
  AppLockState build() => const AppLockState(status: AppLockStatus.unlocked);
}