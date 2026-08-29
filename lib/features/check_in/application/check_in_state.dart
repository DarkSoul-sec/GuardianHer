import 'package:flutter/foundation.dart';

import '../domain/check_in_settings.dart';

/// Immutable view of the Safety Check-In feature shown to the UI.
@immutable
final class CheckInState {
  const CheckInState({
    required this.settings,
    this.missedCount = 0,
    this.isDue = false,
    this.isWorking = false,
    this.statusMessage,
    this.loaded = false,
  });

  /// Configuration is loaded (from storage) when `true`. Until then the UI
  /// must not let the user toggle settings or a false "disabled" state flash.
  final bool loaded;

  final CheckInSettings settings;

  /// Number of consecutive check-ins that passed without acknowledgment.
  /// Drives the urgency wording of the next message.
  final int missedCount;

  /// Whether a check-in is currently due and awaiting the user's response.
  final bool isDue;

  /// A check-in acknowledge/enable operation is in flight.
  final bool isWorking;

  /// Short, honest status text (e.g. "Check-in message opened for sending.").
  final String? statusMessage;

  CheckInState copyWith({
    bool? loaded,
    CheckInSettings? settings,
    int? missedCount,
    bool? isDue,
    bool? isWorking,
    String? Function()? statusMessage,
  }) {
    return CheckInState(
      loaded: loaded ?? this.loaded,
      settings: settings ?? this.settings,
      missedCount: missedCount ?? this.missedCount,
      isDue: isDue ?? this.isDue,
      isWorking: isWorking ?? this.isWorking,
      statusMessage:
          statusMessage != null ? statusMessage() : this.statusMessage,
    );
  }
}