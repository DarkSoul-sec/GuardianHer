/// Immutable configuration for one simulated incoming call.
///
/// Everything here is display-only: [callerName] and [callerNumber] are shown
/// on the fake incoming-call screen and never dialled. No telephony, SMS,
/// GPS, microphone or network is involved.
class FakeCallConfig {
  const FakeCallConfig({
    this.callerName = 'Mom',
    this.callerNumber = 'Incoming Call',
    this.delay = FakeCallDelay.seconds10,
    this.vibrationEnabled = true,
  });

  /// Display name shown on the incoming-call screen.
  final String callerName;

  /// Display-only number label. Never dialled.
  final String callerNumber;

  /// How long to wait before the fake incoming call appears.
  final FakeCallDelay delay;

  /// Whether the device vibrates while the fake call is ringing.
  final bool vibrationEnabled;

  FakeCallConfig copyWith({
    String? callerName,
    String? callerNumber,
    FakeCallDelay? delay,
    bool? vibrationEnabled,
  }) {
    return FakeCallConfig(
      callerName: callerName ?? this.callerName,
      callerNumber: callerNumber ?? this.callerNumber,
      delay: delay ?? this.delay,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FakeCallConfig &&
      other.callerName == callerName &&
      other.callerNumber == callerNumber &&
      other.delay == delay &&
      other.vibrationEnabled == vibrationEnabled;

  @override
  int get hashCode =>
      Object.hash(callerName, callerNumber, delay, vibrationEnabled);
}

/// Closed set of scheduling delays (product-mandated).
enum FakeCallDelay {
  seconds5('5 seconds', Duration(seconds: 5)),
  seconds10('10 seconds', Duration(seconds: 10)),
  seconds30('30 seconds', Duration(seconds: 30)),
  minute1('1 minute', Duration(minutes: 1));

  const FakeCallDelay(this.label, this.duration);

  final String label;
  final Duration duration;
}
