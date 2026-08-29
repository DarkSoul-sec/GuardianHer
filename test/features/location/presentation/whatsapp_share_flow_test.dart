import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/application/contacts_controller.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/application/contacts_state.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/location/presentation/location_screen.dart';

import '../../../helpers/fakes.dart';
import '../../sos/sos_test_fakes.dart';

class _StubContacts extends ContactsController {
  _StubContacts(this.contacts);

  final List<TrustedContact> contacts;

  @override
  ContactsState build() => ContactsLoaded(contacts: contacts);
}

void main() {
  final alice = TrustedContact.create(
    name: 'Alice',
    phoneNumber: '+919876543210',
    priority: 1,
  );

  Future<(ProviderContainer, FakeWhatsAppService)> pumpCaptured(
    WidgetTester tester, {
    FakeWhatsAppService? whatsapp,
    List<TrustedContact> contacts = const [],
    FakeSmsService? sms,
    FakeShareService? share,
  }) async {
    final wa = whatsapp ?? FakeWhatsAppService();
    final container = createContainer(
      overrides: [
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
        whatsappServiceProvider.overrideWithValue(wa),
        if (sms != null) smsServiceProvider.overrideWithValue(sms),
        if (share != null) shareServiceProvider.overrideWithValue(share),
        contactsControllerProvider.overrideWith(() => _StubContacts(contacts)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LocationScreen()),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Get Current Location'));
    await tester.pump();
    await tester.pump();
    return (container, wa);
  }

  testWidgets('one tap opens WhatsApp for the chosen contact exactly once',
      (tester) async {
    final (container, wa) = await pumpCaptured(
      tester,
      contacts: [alice],
    );

    await tester.tap(find.text('Send via WhatsApp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(wa.opened, hasLength(1));
    // The service received the raw stored number; canonicalization is its job.
    expect(wa.opened.single.phoneNumber, alice.phoneNumber);
    expect(find.text('WhatsApp chat opened.'), findsOneWidget);
    // Sanity: the session state still holds the captured fix.
    expect(
      container.read(locationControllerProvider).status,
      LocationStatus.captured,
    );
  });

  testWidgets('an unopenable chat shows the graceful fallback dialog with '
      'both alternative channels', (tester) async {
    final sms = FakeSmsService();
    final share = FakeShareService();
    final (_, wa) = await pumpCaptured(
      tester,
      contacts: [alice],
      whatsapp:
          FakeWhatsAppService()..result = const Err(NoWhatsAppAppAvailableFailure()),
      sms: sms,
      share: share,
    );

    await tester.tap(find.text('Send via WhatsApp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text("WhatsApp isn't available for this contact."),
        findsOneWidget);
    expect(find.text('Send via SMS'), findsOneWidget);
    expect(find.text('Share another way'), findsOneWidget);
    // No crash and no repeated launch loop: still exactly one attempt.
    expect(wa.opened, hasLength(1));

    // "Share another way" hands the same message to the system share sheet.
    await tester.tap(find.text('Share another way'));
    await tester.pumpAndSettle();
    expect(share.shared, hasLength(1));
    expect(share.shared.single, contains('GuardianHer SOS alert'));
    expect(sms.opened, isEmpty);
  });

  testWidgets('the SMS fallback opens the composer for the chosen contact',
      (tester) async {
    final sms = FakeSmsService();
    final share = FakeShareService();
    await pumpCaptured(
      tester,
      contacts: [alice],
      whatsapp:
          FakeWhatsAppService()..result = const Err(NoWhatsAppAppAvailableFailure()),
      sms: sms,
      share: share,
    );

    await tester.tap(find.text('Send via WhatsApp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send via SMS'));
    await tester.pumpAndSettle();

    expect(sms.opened, hasLength(1));
    expect(sms.opened.single.phoneNumber, '919876543210');
    expect(sms.opened.single.body, contains('maps.google.com'));
    expect(share.shared, isEmpty);
  });

  testWidgets('without trusted contacts the flow explains instead of '
      'launching', (tester) async {
    final (_, wa) = await pumpCaptured(tester);

    await tester.tap(find.text('Send via WhatsApp'));
    await tester.pump();

    expect(wa.opened, isEmpty);
    expect(find.text('No trusted contacts yet.'), findsNothing);
    expect(
      find.textContaining('No trusted contacts yet'),
      findsOneWidget,
    );
  });
}
