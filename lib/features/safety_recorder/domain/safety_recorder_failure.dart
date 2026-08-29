import '../../../core/error/failures.dart';

/// Failure types specific to the Safety Recorder feature.
///
/// The recorder is an observer: failures here must NEVER propagate to
/// SOS, Journey, Location, Communication, or Check-In. All public
/// recorder paths swallow these internally via [Result].
sealed class SafetyRecorderFailure extends Failure {
  const SafetyRecorderFailure({required super.message, super.code});
}

/// The rolling buffer or incident event list exceeded its capacity.
final class BufferOverflowFailure extends SafetyRecorderFailure {
  const BufferOverflowFailure([
    String message = 'The event buffer is full.',
  ]) : super(message: message, code: 'buffer_overflow');
}

/// The incident storage is corrupted or contains invalid data.
final class CorruptedIncidentDataFailure extends SafetyRecorderFailure {
  const CorruptedIncidentDataFailure([
    String message = 'Incident data is corrupted.',
  ]) : super(message: message, code: 'corrupted_incident_data');
}

/// The storage format version is newer than supported.
final class UnsupportedStorageVersionFailure extends SafetyRecorderFailure {
  const UnsupportedStorageVersionFailure([
    String message = 'Incident storage version is not supported.',
  ]) : super(message: message, code: 'unsupported_storage_version');
}

/// The integrity chain verification failed.
final class IntegrityVerificationFailure extends SafetyRecorderFailure {
  const IntegrityVerificationFailure([
    String message = 'Integrity verification failed.',
  ]) : super(message: message, code: 'integrity_verification');
}

/// The maximum number of retained incidents has been reached.
final class IncidentRetentionLimitFailure extends SafetyRecorderFailure {
  const IncidentRetentionLimitFailure([
    String message = 'Maximum incident retention limit reached.',
  ]) : super(message: message, code: 'incident_retention_limit');
}
