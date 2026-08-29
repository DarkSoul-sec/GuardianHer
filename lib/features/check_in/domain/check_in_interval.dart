import 'package:flutter/foundation.dart';

/// Selectable check-in intervals.
///
/// Kept as a CLOSED, product-mandated set (1 h / 2 h / 3 h only): no custom
/// intervals in V1, so the scheduling math (whole-minute intervals) and the
/// settings UI share one source of truth.
enum CheckInInterval {
  minutes60(60),
  minutes120(120),
  minutes180(180),

  /// DEBUG-ONLY 2-minute interval for real-device alarm-path validation.
  /// Excluded from [selectable] in release builds, so it can never be chosen
  /// or restored as a production option.
  devTest2(2);

  const CheckInInterval(this.minutes);

  /// Interval length in whole minutes.
  final int minutes;

  Duration get duration => Duration(minutes: minutes);

  /// Plain-language label shown in the settings UI.
  String get label => switch (this) {
        CheckInInterval.minutes60 => 'Every 1 hour',
        CheckInInterval.minutes120 => 'Every 2 hours',
        CheckInInterval.minutes180 => 'Every 3 hours',
        CheckInInterval.devTest2 => 'Every 2 minutes (TEST)',
      };

  /// Intervals the user may pick. The test interval exists only in debug
  /// builds (`flutter run`/debug APK); release builds offer exactly the
  /// product set and also REFUSE to restore a stored test value.
  static List<CheckInInterval> get selectable => kDebugMode
      ? values
      : values.where((interval) => interval != devTest2).toList();

  /// Resolves a stored interval by minute count. Unknown minute counts fall
  /// back to the default (1 hour); this includes the debug-only test value,
  /// which release builds treat as corrupt data on purpose.
  static CheckInInterval fromMinutes(int minutes) {
    for (final interval in selectable) {
      if (interval.minutes == minutes) {
        return interval;
      }
    }
    return CheckInInterval.minutes60;
  }
}