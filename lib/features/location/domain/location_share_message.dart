import 'location_format.dart';
import 'location_point.dart';

/// Builds the shareable web-Maps URL for [point].
///
/// A `https://maps.google.com/?q=lat,lng` link is tappable from messaging apps,
/// unlike the raw `geo:` scheme, so it is used for the share message.
String buildMapsShareUrl(LocationPoint point) {
  return 'https://maps.google.com/?q=${point.latitude},${point.longitude}';
}

/// The default location share message.
///
/// Centralized here so the wording can be changed in one place. The user
/// explicitly initiates every share; nothing is ever sent automatically.
///
/// A fresh fix is labeled "Current location captured at HH:MM"; a cached
/// fallback is always labeled "Last known location captured at HH:MM" so a
/// stale position is never presented as current.
String buildLocationShareMessage(LocationPoint point) {
  final label = point.isStale ? 'Last known location' : 'Current location';
  return 'GuardianHer SOS alert\n'
      '$label captured at ${formatCapturedTime(point.capturedAt)}\n'
      '${buildMapsShareUrl(point)}';
}
