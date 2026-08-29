import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/vehicle_info.dart';

/// App-scoped holder of the vehicle context attached to the CURRENT safety
/// story (Phase D).
///
/// WHY IT EXISTS: the journey and SOS are separate pipelines (deliberately
/// never redesigned into each other), but requirement: when a journey
/// escalates to SOS, the emergency must still show WHICH vehicle the user is
/// in without re-entry. This provider is the read-only seam between them.
///
/// LIFECYCLE (enforced by JourneyController):
/// 1. set when a journey starts with vehicle information;
/// 2. SURVIVES the journey→SOS escalation (that is its whole purpose);
/// 3. cleared when the emergency ends AND no journey owns it anymore, or
///    when a completed journey's summary is dismissed;
/// 4. NEVER persisted — process death simply loses it (honest: a fresh app
///    open cannot know which vehicle the user is in).
///
/// PRIVACY: consumers may DISPLAY it; nothing may log, persist, upload or
/// embed it in URLs/ids.
final emergencyVehicleContextProvider =
    StateProvider<VehicleInfo?>((ref) => null);
