import 'package:flutter/foundation.dart';

/// How the notification subsystem is behaving for the current session.
enum SosNotificationStatus {
  /// No session has requested or shown a notification yet.
  unknown,

  /// Permission granted and the SOS alert is currently showing.
  active,

  /// The alert is being removed while the session stops.
  stopping,

  /// Notifications are unavailable (denied or platform error); SOS stays
  /// active regardless.
  unavailable,
}

/// State of the bounded SOS vibration for the current session.
enum SosVibrationStatus {
  /// No vibration is running (not started or already stopped).
  idle,

  /// The one-shot SOS alert pattern is running.
  active,

  /// Vibration could not start (no vibrator or platform error).
  failed,
}

/// Notification permission as last observed by the coordinator.
enum SosNotificationPermission {
  unknown,
  granted,
  denied,
}

/// Kinds of emergency actions the user can deliberately trigger.
enum SosActionKind {
  callContact,
  messageContact,
  callEmergency,
}

/// A truthful, human-readable outcome of a user-triggered emergency action.
///
/// [message] never claims more than actually happened: a dialer/SMS composer
/// can be *opened*, never a call *placed* or a message *sent*.
@immutable
final class SosActionOutcome {
  const SosActionOutcome.success(this.kind, this.message) : isSuccess = true;

  const SosActionOutcome.failure(this.kind, this.message) : isSuccess = false;

  final SosActionKind kind;
  final String message;
  final bool isSuccess;
}

/// Side-effect state kept by the [SosActionController] while it coordinates
/// vibration, notifications, dialer and SMS for an SOS session.
@immutable
final class SosActionsState {
  const SosActionsState({
    this.notificationPermission = SosNotificationPermission.unknown,
    this.notificationStatus = SosNotificationStatus.unknown,
    this.vibrationStatus = SosVibrationStatus.idle,
    this.lastOutcome,
  });

  final SosNotificationPermission notificationPermission;
  final SosNotificationStatus notificationStatus;
  final SosVibrationStatus vibrationStatus;
  final SosActionOutcome? lastOutcome;

  SosActionsState copyWith({
    SosNotificationPermission? notificationPermission,
    SosNotificationStatus? notificationStatus,
    SosVibrationStatus? vibrationStatus,
    SosActionOutcome? Function()? lastOutcome,
  }) {
    return SosActionsState(
      notificationPermission:
          notificationPermission ?? this.notificationPermission,
      notificationStatus: notificationStatus ?? this.notificationStatus,
      vibrationStatus: vibrationStatus ?? this.vibrationStatus,
      lastOutcome: lastOutcome != null ? lastOutcome() : this.lastOutcome,
    );
  }

  /// Short, truthful status fragments shown on the SOS ACTIVE screen.
  List<String> get statusFragments {
    return [
      switch (notificationStatus) {
        SosNotificationStatus.active => 'SOS alert active',
        SosNotificationStatus.stopping => 'Removing notification',
        SosNotificationStatus.unavailable =>
          'Notifications unavailable — SOS remains active',
        SosNotificationStatus.unknown => null,
      },
      switch (vibrationStatus) {
        SosVibrationStatus.active => 'Vibration alerting',
        SosVibrationStatus.failed => 'Vibration unavailable',
        SosVibrationStatus.idle => null,
      },
    ].whereType<String>().toList();
  }
}