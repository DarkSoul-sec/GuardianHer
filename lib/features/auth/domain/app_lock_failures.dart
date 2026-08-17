import '../../../core/error/failures.dart';

/// Base type for app-lock failures.
sealed class AppLockFailure extends Failure {
  const AppLockFailure({
    super.message = 'A lock error occurred.',
    super.code,
  });
}

/// The two PIN entries did not match.
final class PinMismatchFailure extends AppLockFailure {
  const PinMismatchFailure({
    super.message = 'The PINs do not match.',
    super.code = 'pin_mismatch',
  });
}

/// The PIN does not satisfy the length/format policy.
final class InvalidPinLengthFailure extends AppLockFailure {
  const InvalidPinLengthFailure({
    super.message = 'The PIN must be 6 digits.',
    super.code = 'invalid_pin',
  });
}

/// The supplied PIN is incorrect.
final class PinVerificationFailure extends AppLockFailure {
  const PinVerificationFailure({
    super.message = 'Incorrect PIN.',
    super.code = 'pin_incorrect',
  });
}

/// The user is temporarily locked out due to repeated failures.
final class LockedOutFailure extends AppLockFailure {
  const LockedOutFailure(
    this.remaining, {
    super.message = 'Too many incorrect attempts.',
    super.code = 'locked_out',
  });

  final Duration remaining;
}

/// A PIN already exists, so the setup operation is not allowed.
final class PinAlreadySetFailure extends AppLockFailure {
  const PinAlreadySetFailure({
    super.message = 'A PIN is already configured.',
    super.code = 'pin_already_set',
  });
}

/// Biometrics are not available on this device.
final class BiometricNotAvailableFailure extends AppLockFailure {
  const BiometricNotAvailableFailure({
    super.message = 'Biometrics are not available on this device.',
    super.code = 'biometric_unavailable',
  });
}

/// Biometric unlock is turned off in security settings.
final class BiometricDisabledFailure extends AppLockFailure {
  const BiometricDisabledFailure({
    super.message = 'Biometric unlock is disabled.',
    super.code = 'biometric_disabled',
  });
}

/// Biometric authentication did not succeed.
final class BiometricFailedFailure extends AppLockFailure {
  const BiometricFailedFailure({
    super.message = 'Biometric authentication failed.',
    super.code = 'biometric_failed',
  });
}

/// Stored authentication data is unreadable or corrupted.
final class CorruptedAuthDataFailure extends AppLockFailure {
  const CorruptedAuthDataFailure({
    super.message = 'The stored security data is corrupted.',
    super.code = 'corrupted_auth_data',
  });
}