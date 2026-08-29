import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/live_location_api_client.dart';
import '../domain/live_location_session.dart';
import 'live_location_controller.dart';
import 'live_location_state.dart';

/// Injected clock for expiry decisions (fake in tests).
final liveClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// GuardianHer live-location backend client. Base URL comes from
/// `--dart-define=GUARDIANHER_LIVE_API_URL`; unconfigured builds keep the
/// feature visibly disabled rather than guessing an endpoint (§28).
final liveLocationApiClientProvider = Provider<LiveLocationApiClient>(
  (ref) => HttpLiveLocationApiClient(),
);

/// Cheap configuration probe so the UI can explain an unconfigured build
/// without touching the client.
final liveLocationApiConfiguredProvider = Provider<bool>(
  (ref) => ref.watch(liveLocationApiClientProvider).isConfigured,
);

/// Emergency sessions use the faster cadence and this window. 60 minutes
/// covers the realistic span of an SOS incident without inviting
/// set-and-forget tracking; the server caps every duration anyway.
final liveSosDurationProvider = Provider<LiveShareDuration>(
  (ref) => LiveShareDuration.minutes60,
);

/// The live-location workflow controller.
final liveLocationControllerProvider =
    NotifierProvider<LiveLocationController, LiveLocationState>(
  LiveLocationController.new,
);
