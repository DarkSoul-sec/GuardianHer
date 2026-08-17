/// Centralized error model shared across all features.
///
/// Operations return [Result]s carrying a [Failure] instead of throwing
/// platform exceptions across layer boundaries. Concrete subclasses (in other
/// libraries) describe the failure category so UI code can map them to
/// user-facing messages without leaking platform-specific exceptions into
/// widgets.
abstract class Failure {
  const Failure({required this.message, this.code});

  final String message;
  final String? code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// An unexpected, category-agnostic failure.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([String message = 'An unexpected error occurred.'])
      : super(message: message, code: 'unexpected');
}

/// A failure reported by a platform/device integration (e.g. plugin error).
final class PlatformFailure extends Failure {
  const PlatformFailure([String message = 'A platform error occurred.'])
      : super(message: message, code: 'platform');
}

/// A failure reading or writing persistent storage.
final class StorageFailure extends Failure {
  const StorageFailure([String message = 'A storage error occurred.'])
      : super(message: message, code: 'storage');
}

/// A failure caused by a denied OS permission.
final class PermissionDeniedFailure extends Failure {
  const PermissionDeniedFailure([String message = 'Permission was denied.'])
      : super(message: message, code: 'permission_denied');
}