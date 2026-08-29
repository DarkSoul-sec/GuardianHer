import '../../../core/error/failures.dart';

/// Why a live-location operation failed. Presentation maps each value to
/// honest, actionable copy; nothing here claims delivery that did not happen.
enum LiveLocationFailureType {
  /// No API base URL configured for this build (dart-define).
  notConfigured('not_configured'),

  /// The device has no usable network path right now.
  networkUnavailable('network_unavailable'),

  /// The backend could not be reached (DNS, TLS, 5xx, timeout).
  serverUnavailable('server_unavailable'),

  /// The backend refused the request shape or rate-limited us.
  rejectedByServer('rejected_by_server'),

  /// The backend reports the session ended (TTL elapsed).
  sessionExpired('session_expired'),

  /// The session was stopped; the URL is dead.
  sessionRevoked('session_revoked'),

  /// The response could not be trusted (malformed JSON, missing fields).
  invalidResponse('invalid_response');

  const LiveLocationFailureType(this.code);

  /// Stable machine-readable code — safe for diagnostics.
  final String code;
}

final class LiveLocationFailure extends Failure {
  LiveLocationFailure(this.type, {String? detail})
      : super(
          message: detail ?? 'Live location failure: ${type.name}.',
          code: type.code,
        );

  final LiveLocationFailureType type;

  @override
  String toString() => 'LiveLocationFailure(${type.name})';
}
