/// The kind of safety activity a [SafetySession] coordinates.
///
/// The session layer is deliberately small: it records *which* safety feature
/// is running so cross-cutting concerns (Safe Journey + SOS fusion, the Safety
/// Recorder) have one place to look. It does not replace the feature-internal
/// state machines (SOS state machine, live-location lifecycle), which remain
/// authoritative for their own behavior.
enum SafetySessionType {
  /// An active SOS emergency (button, shake, widget or tile entry point).
  sos,

  /// User-initiated live location sharing.
  liveLocation,

  /// A Safe Journey: travelling with continuous location sharing and optional
  /// vehicle information attached.
  safeJourney;

  /// Stable wire/storage token for this type.
  String get storageName => switch (this) {
        SafetySessionType.sos => 'sos',
        SafetySessionType.liveLocation => 'live_location',
        SafetySessionType.safeJourney => 'safe_journey',
      };

  /// Parses a storage token produced by [storageName]; returns `null` for
  /// unknown tokens instead of guessing.
  static SafetySessionType? tryParse(String value) => switch (value) {
        'sos' => SafetySessionType.sos,
        'live_location' => SafetySessionType.liveLocation,
        'safe_journey' => SafetySessionType.safeJourney,
        _ => null,
      };
}
