import 'package:local_auth/local_auth.dart';

import '../../core/error/failures.dart';
import '../../core/platform/biometric_service.dart';
import '../../core/result/result.dart';

/// Device biometric authentication backed by local_auth.
class LocalAuthBiometricService implements BiometricService {
  LocalAuthBiometricService({LocalAuthentication? authentication})
      : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _authentication.isDeviceSupported()) return false;
      if (!await _authentication.canCheckBiometrics) return false;
      final enrolled = await _authentication.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Future<Result<bool>> authenticate({required String reason}) async {
    try {
      final granted = await _authentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return Ok(granted);
    } on Exception {
      // Covers canceled auth, lockout, and platform rejection: the caller
      // falls back to PIN verification.
      return Ok(false);
    } on Error {
      return const Err(PlatformFailure('Biometric authentication is unavailable.'));
    }
  }
}