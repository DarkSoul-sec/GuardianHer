/// The state of the local app lock.
enum AppLockStatus {
  /// Lock state has not been resolved yet (initializing).
  unknown,

  /// No PIN is stored; the user must create one (first launch or after reset).
  needsSetup,

  /// A PIN is stored and the app is locked.
  locked,

  /// Stored authentication data is unavailable or corrupted. Fail closed:
  /// the app stays locked until the user resets the lock.
  corrupted,

  /// The app is unlocked.
  unlocked,
}