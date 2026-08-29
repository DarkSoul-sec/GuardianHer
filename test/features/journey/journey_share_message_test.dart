import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/features/journey/application/journey_share_message.dart';
import 'package:guardianher/features/journey/domain/vehicle_info.dart';

void main() {
  final startedAt = DateTime(2026, 1, 1, 12, 5);

  test('includes the live link and its honest expiry time', () {
    final message = buildJourneyShareMessage(
      startedAt: startedAt,
      shareUrl: 'https://live.example.org/live/abc',
      expiresAt: DateTime(2026, 1, 1, 14, 5),
    );
    expect(message, contains("I'm on a journey"));
    expect(message, contains('Journey started at 12:05.'));
    expect(message, contains('Live location: https://live.example.org/live/abc'));
    expect(message, contains('This link expires at 14:05.'));
  });

  test('without a link it says so instead of pretending', () {
    final message = buildJourneyShareMessage(startedAt: startedAt);
    expect(message, isNot(contains('Live location:')));
    expect(message, contains('The live link is not active right now.'));
  });

  test('vehicle section included ONLY when explicitly passed', () {
    const vehicle = VehicleInfo(
      type: VehicleType.taxi,
      registrationNumber: 'DL01AB1234',
      driverName: 'Ramesh',
      bookingReference: 'UB-771234',
    );
    final message = buildJourneyShareMessage(
      startedAt: startedAt,
      shareUrl: 'https://live.example.org/live/abc',
      expiresAt: DateTime(2026, 1, 1, 14, 5),
      vehicle: vehicle,
    );
    expect(message, contains('Vehicle: Taxi'));
    expect(message, contains('Registration: DL 01 AB 1234'));
    // Driver name and booking reference stay OUT of shares (minimum useful
    // safety context only).
    expect(message.contains('Ramesh'), isFalse);
    expect(message.contains('UB-771234'), isFalse);
  });

  test('no vehicle passed means no vehicle lines at all', () {
    final message = buildJourneyShareMessage(
      startedAt: startedAt,
      shareUrl: 'https://live.example.org/live/abc',
    );
    expect(message.contains('Vehicle:'), isFalse);
    expect(message.contains('Registration:'), isFalse);
  });

  test('the registration never leaks into the share URL', () {
    const vehicle = VehicleInfo(
      type: VehicleType.taxi,
      registrationNumber: 'DL01AB1234',
    );
    final url = 'https://live.example.org/live/abc';
    final message = buildJourneyShareMessage(
      startedAt: startedAt,
      shareUrl: url,
      vehicle: vehicle,
    );
    // The ONLY URL in the message is the opaque-token link.
    final urlLines = message
        .split('\n')
        .where((line) => line.startsWith('Live location:'))
        .toList();
    expect(urlLines, ['Live location: $url']);
    expect(message.contains('/DL01AB1234'), isFalse);
    expect(url.contains('DL01AB1234'), isFalse);
  });

  test('never claims anyone is monitoring the journey', () {
    final message = buildJourneyShareMessage(
      startedAt: startedAt,
      shareUrl: 'https://live.example.org/live/abc',
      expiresAt: DateTime(2026, 1, 1, 14, 5),
    );
    final lower = message.toLowerCase();
    expect(lower.contains('monitored'), isFalse);
    expect(lower.contains('being watched'), isFalse);
    expect(lower.contains('sent'), isFalse,
        reason: 'opening a composer is not a delivery claim');
  });
}
