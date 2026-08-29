import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';

import '../../../helpers/fakes.dart';

void main() {
  ProviderContainer containerWith({
    FakeWhatsAppService? whatsapp,
  }) {
    return createContainer(
      overrides: [
        if (whatsapp != null)
          whatsappServiceProvider.overrideWithValue(whatsapp),
      ],
    );
  }

  test('shareViaWhatsApp fails truthfully without a captured point',
      () async {
    final whatsapp = FakeWhatsAppService();
    final container = containerWith(whatsapp: whatsapp);
    addTearDown(container.dispose);

    final result = await container
        .read(locationControllerProvider.notifier)
        .shareViaWhatsApp(_alice);

    expect(result, isA<Err<void>>());
    expect((result as Err<void>).failure, isA<LocationUnavailableFailure>());
    // Nothing was launched.
    expect(whatsapp.opened, isEmpty);
  });

  test('shareViaWhatsApp hands the contact number and location body to the '
      'service', () async {
    final whatsapp = FakeWhatsAppService();
    final container = containerWith(whatsapp: whatsapp);
    addTearDown(container.dispose);
    final controller = container.read(locationControllerProvider.notifier);

    await controller.captureLocation();
    final result = await controller.shareViaWhatsApp(_alice);

    expect(result, isA<Ok<void>>());
    expect(whatsapp.opened, hasLength(1));
    // The RAW stored digits-only number goes to the service; the service owns
    // canonicalization so every caller gets identical treatment.
    expect(whatsapp.opened.single.phoneNumber, _alice.phoneNumber);
    expect(whatsapp.opened.single.body, contains('GuardianHer SOS alert'));
    expect(
      whatsapp.opened.single.body,
      contains('https://maps.google.com/?q=12.345678,98.765432'),
    );
  });

  test('shareViaWhatsApp propagates a WhatsApp failure without retrying',
      () async {
    final whatsapp = FakeWhatsAppService()
      ..result = const Err(NoWhatsAppAppAvailableFailure());
    final container = containerWith(whatsapp: whatsapp);
    addTearDown(container.dispose);
    final controller = container.read(locationControllerProvider.notifier);

    await controller.captureLocation();
    await controller.shareViaWhatsApp(_alice);
    await controller.shareViaWhatsApp(_alice);

    // Two deliberate user actions, two attempts — never an automatic loop.
    expect(whatsapp.opened, hasLength(2));
  });
}

final _alice = TrustedContact.create(
  name: 'Alice',
  phoneNumber: '919876543210',
  priority: 1,
);
