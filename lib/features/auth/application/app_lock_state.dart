import '../domain/app_lock_status.dart';

/// Immutable view of the local app lock.
class AppLockState {
  const AppLockState({
    required this.status,
    this.biometricsAvailable = false,
    this.attempts = 0,
    this.isLockedOut = false,
    this.lockoutRemaining = Duration.zero,
  });

  final AppLockStatus status;
  final bool biometricsAvailable;
  final int attempts;
  final bool isLockedOut;
  final Duration lockoutRemaining;

  bool get isUnlocked => status == AppLockStatus.unlocked;

  AppLockState copyWith({
    AppLockStatus? status,
    bool? biometricsAvailable,
    int? attempts,
    bool? isLockedOut,
    Duration? lockoutRemaining,
  }) {
    return AppLockState(
      status: status ?? this.status,
      biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
      attempts: attempts ?? this.attempts,
      isLockedOut: isLockedOut ?? this.isLockedOut,
      lockoutRemaining: lockoutRemaining ?? this.lockoutRemaining,
    );
  }
}