/// A locally stored voice note.
///
/// [path] points inside the application's private documents directory.
/// Nothing here ever leaves the device except through the explicit,
/// user-confirmed system share sheet.
class VoiceRecording {
  const VoiceRecording({
    required this.id,
    required this.path,
    required this.createdAt,
    required this.duration,
    required this.displayName,
  });

  final String id;
  final String path;
  final DateTime createdAt;
  final Duration duration;
  final String displayName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'displayName': displayName,
      };

  static VoiceRecording? tryFromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String;
      final path = json['path'] as String;
      final createdAt = DateTime.parse(json['createdAt'] as String);
      final duration = Duration(milliseconds: (json['durationMs'] as num).toInt());
      final displayName = json['displayName'] as String;
      if (id.isEmpty || path.isEmpty || displayName.isEmpty) return null;
      if (duration.isNegative) return null;
      return VoiceRecording(
        id: id,
        path: path,
        createdAt: createdAt,
        duration: duration,
        displayName: displayName,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceRecording &&
      other.id == id &&
      other.path == path &&
      other.createdAt == createdAt &&
      other.duration == duration &&
      other.displayName == displayName;

  @override
  int get hashCode =>
      Object.hash(id, path, createdAt, duration, displayName);
}
