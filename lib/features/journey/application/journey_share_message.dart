import '../../location/domain/location_format.dart';
import '../domain/vehicle_info.dart';

/// Builds the text a user shares when they want someone to follow their
/// journey (Phases C/D). Pure function; no side effects.
///
/// WORDING DISCIPLINE (Phase 3G): never claims anyone is being watched or
/// monitored — it describes what the user chose to share and until when.
///
/// VEHICLE (Phase D): included ONLY when [vehicle] is passed, which happens
/// exclusively on the user's explicit "Send link" tap. The registration is
/// NEVER embedded in any URL — links stay opaque tokens.
String buildJourneyShareMessage({
  required DateTime startedAt,
  String? shareUrl,
  DateTime? expiresAt,
  VehicleInfo? vehicle,
}) {
  final buffer = StringBuffer("I'm on a journey and sharing my live location.");
  final v = vehicle;
  if (v != null) {
    buffer.write('\n\nVehicle: ${v.type.label}');
    final reg = v.displayRegistrationNumber;
    if (reg != null) {
      buffer.write('\nRegistration: $reg');
    }
    buffer.write('\n');
  }
  buffer
    ..writeln()
    ..write('Journey started at ${formatCapturedTime(startedAt)}.');
  final url = shareUrl;
  if (url != null && url.isNotEmpty) {
    buffer
      ..writeln()
      ..write('Live location: $url');
    final expiry = expiresAt;
    if (expiry != null) {
      buffer
        ..writeln()
        ..write('This link expires at ${formatCapturedTime(expiry)}.');
    }
  } else {
    buffer
      ..writeln()
      ..write('The live link is not active right now.');
  }
  return buffer.toString();
}
