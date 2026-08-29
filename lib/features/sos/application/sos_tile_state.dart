import '../../../core/platform/sos_tile.dart';
import '../application/sos_state.dart';

/// Whether the Quick Settings SOS tile reads as ENGAGED for [state].
///
/// The tile shows an engaged (active) state for every phase where the
/// emergency workflow is in progress — including the cancellation countdown,
/// which is still a live emergency until it resolves. Only idle and completed
/// read as inactive. Pure function: single source of truth for the mirror.
bool sosTileEngaged(SosState state) => switch (state) {
      SosIdle() => false,
      SosCountdown() => true,
      SosActive() => true,
      SosCancelling() => true,
      SosCompleted() => false,
    };

/// Fire-and-forget push of the mirrored SOS state onto [service]. Never
/// throws into the caller: a channel failure must not touch the SOS flow.
Future<void> pushSosTileState(SosTileStateService service, SosState state) async {
  if (!isSosTileSupported) return;
  try {
    await service.setEngaged(engaged: sosTileEngaged(state));
  } catch (_) {
    // Best-effort mirror only.
  }
}
