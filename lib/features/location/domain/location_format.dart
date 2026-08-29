/// Pure display formatters for location values.
///
/// Centralized so the Location screen, the SOS active screen and status lines
/// all render the same honest wording. These functions never invent data: an
/// approximate fix is labeled approximate, and a stale fix is labeled by its
/// capture age.
library;

/// Formats a raw accuracy value honestly: meters when small, "approximately"
/// kilometers when large. Never relabels an approximate fix as precise.
String formatAccuracy(double meters) {
  if (meters >= 1000) {
    return 'approximately ${(meters / 1000).toStringAsFixed(1)} km';
  }
  return '${meters.toStringAsFixed(0)} m';
}

/// Formats the UTC capture time in local HH:MM.
String formatCapturedTime(DateTime capturedAtUtc) {
  final local = capturedAtUtc.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Formats how long ago [capturedAtUtc] happened, in coarse human units.
///
/// Used for stale ("last known") fixes: "Updated X minutes ago" tells the user
/// how old the information is without exposing a raw timestamp.
String formatCapturedAge(DateTime capturedAtUtc, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final age = reference.difference(capturedAtUtc.toLocal());
  if (age.inMinutes < 1) {
    return 'Updated less than a minute ago';
  }
  if (age.inMinutes < 60) {
    return 'Updated ${age.inMinutes} minutes ago';
  }
  final hours = age.inHours;
  if (hours < 24) {
    return 'Updated $hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  final days = age.inDays;
  return 'Updated $days ${days == 1 ? 'day' : 'days'} ago';
}
