import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/platform/sos_tile.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';
import 'package:guardianher/features/sos/application/sos_tile_state.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/domain/sos_status.dart';
import '../../helpers/fakes.dart';

void main() {
  final event = SosEvent(
    id: SosEventId.generate(),
    startedAt: DateTime.utc(2026, 1, 1),
    status: SosStatus.active,
    countdownDuration: const Duration(seconds: 5),
  );

  group('sosTileEngaged', () {
    test('engaged during every in-progress phase (incl. cancelling)', () {
      expect(
        sosTileEngaged(SosCountdown(event: event, remainingSeconds: 3)),
        isTrue,
      );
      expect(sosTileEngaged(SosActive(event: event)), isTrue);
      expect(sosTileEngaged(SosCancelling(event: event)), isTrue);
    });

    test('inactive when idle or completed', () {
      expect(sosTileEngaged(const SosIdle()), isFalse);
      expect(
        sosTileEngaged(SosCompleted(event: event)),
        isFalse,
      );
    });
  });

  group('pushSosTileState', () {
    test('pushes the mapped engagement through the service seam', () async {
      final tile = TestSosTileStateService();

      await pushSosTileState(tile, const SosIdle());
      expect(tile.lastEngaged, isFalse);

      await pushSosTileState(
        tile,
        SosCountdown(event: event, remainingSeconds: 5),
      );
      expect(tile.lastEngaged, isTrue);
      expect(tile.setEngagedCalls, 2);
    });

    test('a failing mirror never throws into the SOS flow', () async {
      await pushSosTileState(_ThrowingSosTileStateService(), const SosIdle());
    });
  });
}

class _ThrowingSosTileStateService implements SosTileStateService {
  @override
  Future<void> setEngaged({required bool engaged}) async {
    throw StateError('channel unavailable');
  }
}
