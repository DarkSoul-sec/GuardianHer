import '../../location/domain/location_point.dart';
import '../../location/domain/location_share_message.dart';

/// Builds the check-in message body.
///
/// Honest by construction: if no location fix was available the body says so
/// (a check-in is never silently location-less), and a positive [missedCount]
/// prefixes an explicit "I missed my previous check-in(s)" escalation. The
/// wording stays plain and jargon-free per the product brief.
String buildCheckInMessageBody({
  LocationPoint? point,
  required int missedCount,
}) {
  final escalation = missedCount > 0 ? 'I missed my previous check-in(s). ' : '';
  final location = point == null
      ? 'I could not share my location right now.'
      : point.isStale
          ? 'My LAST KNOWN location (from ${point.capturedAt.toUtc().toIso8601String()}): ${buildMapsShareUrl(point)}'
          : 'My location: ${buildMapsShareUrl(point)}';
  return '${escalation}Safety check-in from GuardianHer. $location';
}