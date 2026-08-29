import '../../../core/error/failures.dart';

/// The check-in cannot be enabled without at least one trusted recipient.
final class CheckInNoRecipientsFailure extends Failure {
  const CheckInNoRecipientsFailure([
    String message = 'Choose at least one trusted contact to receive your '
        'check-in.',
  ]) : super(message: message, code: 'check_in_no_recipients');
}

/// A check-in reminder could not be scheduled on the device.
final class CheckInSchedulingFailure extends Failure {
  const CheckInSchedulingFailure([
    String message = 'Your next check-in could not be scheduled.',
  ]) : super(message: message, code: 'check_in_scheduling');
}

/// No messaging app could receive the check-in message (user-confirmed send).
final class CheckInSenderFailure extends Failure {
  const CheckInSenderFailure([
    String message = 'No messaging app was found to send your check-in.',
  ]) : super(message: message, code: 'check_in_sender');
}

/// The user's current location could not be captured for the check-in.
final class CheckInLocationUnavailableFailure extends Failure {
  const CheckInLocationUnavailableFailure([
    String message = 'Your location could not be determined. Your check-in '
        'was still sent without it.',
  ]) : super(message: message, code: 'check_in_location_unavailable');
}