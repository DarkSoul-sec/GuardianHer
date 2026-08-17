import '../../../core/error/failures.dart';

/// Base type for settings feature failures.
sealed class SettingsFailure extends Failure {
  const SettingsFailure({
    super.message = 'A settings error occurred.',
    super.code,
  });
}

/// Biometrics could not be used to verify the user while enabling them.
final class BiometricSetupFailure extends SettingsFailure {
  const BiometricSetupFailure({
    super.message = 'Biometrics are not available or were not verified.',
    super.code = 'biometric_setup',
  });
}