import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/data/contacts_repository_impl.dart';
import 'package:guardianher/features/contacts/presentation/contact_form_screen.dart';
import 'package:guardianher/features/contacts/presentation/contacts_screen.dart';

import '../../helpers/fakes.dart';
import 'contacts_test_fakes.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const GuardianHerApp(),
  );
}

ProviderContainer _container({FakeSecureStorageService? storage}) {
  return createContainer(
    overrides: [
      secureStorageServiceProvider.overrideWithValue(
        storage ?? FakeSecureStorageService(),
      ),
    ],
  );
}

Future<void> _seed(
  FakeSecureStorageService storage,
  List<(String, String)> contacts,
) async {
  final repository = SecureStorageContactsRepository(storage: storage);
  for (final (name, phone) in contacts) {
    await repository.addContact(name: name, phoneNumber: phone);
  }
}

Future<void> _openContacts(
  WidgetTester tester,
  ProviderContainer container, {
  bool settle = true,
}) async {
  await tester.pumpWidget(_harness(container));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(find.text('Contacts'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _masked(String phone) {
  if (phone.length <= 4) return phone;
  return '${'•' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
}

void main() {
  group('ContactsScreen', () {
    testWidgets('shows an empty state when no contacts exist', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      expect(find.text('Trusted Contacts'), findsOneWidget);
      expect(find.text('No trusted contacts yet'), findsOneWidget);
      expect(find.text('Add contact'), findsOneWidget);
    });

    testWidgets('lists contacts with masked numbers and priorities',
        (tester) async {
      final storage = FakeSecureStorageService();
      await _seed(storage, [
        ('Mom', '+91 12345 67890'),
        ('Dad', '+91 98765 43210'),
      ]);
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      expect(find.text('Mom'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);
      expect(find.text('Priority 1'), findsOneWidget);
      expect(find.text('Priority 2'), findsOneWidget);

      expect(find.text(_masked('911234567890')), findsOneWidget);
      expect(find.text(_masked('919876543210')), findsOneWidget);
      expect(find.text('911234567890'), findsNothing);
      expect(find.text('919876543210'), findsNothing);
    });

    testWidgets('masked numbers carry an accessible label', (tester) async {
      final storage = FakeSecureStorageService();
      await _seed(storage, [('Mom', '+91 12345 67890')]);
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      final node = tester.getSemantics(
        find
            .ancestor(
              of: find.text(_masked('911234567890')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.label, contains('Phone number ending 7890'));
    });

    testWidgets('add flow saves a contact and returns to the list',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      await tester.tap(find.text('Add contact'));
      await tester.pumpAndSettle();
      expect(find.byType(AddContactScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Mom');
      await tester.enterText(find.byType(TextFormField).at(1), '+91 12345 67890');
      await tester.tap(find.widgetWithText(FilledButton, 'Save contact'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(find.text('Mom'), findsOneWidget);
      expect(find.text(_masked('911234567890')), findsOneWidget);
      expect(find.text('911234567890'), findsNothing);
    });

    testWidgets('add form shows validation errors', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      await tester.tap(find.text('Add contact'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save contact'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Mom');
      await tester.enterText(find.byType(TextFormField).at(1), '123');
      await tester.tap(find.widgetWithText(FilledButton, 'Save contact'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a valid phone number (7–15 digits).'),
        findsOneWidget,
      );
      expect(find.byType(AddContactScreen), findsOneWidget);
    });

    testWidgets('add form rejects a duplicate phone number', (tester) async {
      final storage = FakeSecureStorageService();
      await _seed(storage, [('Mom', '+911234567890')]);
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      await tester.tap(find.text('Add contact'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Dad');
      await tester.enterText(find.byType(TextFormField).at(1), '1234567890');
      await tester.tap(find.widgetWithText(FilledButton, 'Save contact'));
      await tester.pumpAndSettle();

      expect(
        find.text('This phone number is already a trusted contact.'),
        findsOneWidget,
      );
      expect(find.byType(AddContactScreen), findsOneWidget);
    });

    testWidgets('add is blocked when the maximum is reached', (tester) async {
      final storage = FakeSecureStorageService();
      await _seed(storage, [
        ('A', '9111111111'),
        ('B', '9222222222'),
        ('C', '9333333333'),
        ('D', '9444444444'),
        ('E', '9555555555'),
      ]);
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      await tester.tap(find.text('Add contact'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'F');
      await tester.enterText(find.byType(TextFormField).at(1), '9666666666');
      await tester.tap(find.widgetWithText(FilledButton, 'Save contact'));
      await tester.pumpAndSettle();

      expect(find.text('You can add up to 5 trusted contacts.'), findsOneWidget);
      expect(find.byType(AddContactScreen), findsOneWidget);
    });

    testWidgets('edit flow prefills and updates the contact', (tester) async {
      final storage = FakeSecureStorageService();
      await _seed(storage, [('Mom', '+91 12345 67890')]);
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(EditContactScreen), findsOneWidget);

      // Prefilled with the stored values; the +91 prefix is applied for the
      // national number only, so the field shows the bare digits.
      expect(
        find.descendant(
          of: find.byType(EditContactScreen),
          matching: find.text('Mom'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(EditContactScreen),
          matching: find.text('1234567890'),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'Mother');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(find.text('Mother'), findsOneWidget);
      expect(find.text('Mom'), findsNothing);
    });

    testWidgets('delete requires confirmation and cancel keeps the contact',
        (tester) async {
      final storage = FakeSecureStorageService();
      await _seed(storage, [
        ('Mom', '+911234567890'),
        ('Dad', '+919876543210'),
      ]);
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete trusted contact?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Mom'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);

      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Mom'), findsNothing);
      expect(find.text('Dad'), findsOneWidget);
    });

    testWidgets('shows a loading indicator while loading', (tester) async {
      final container = createContainer(
        overrides: [
          contactsControllerProvider.overrideWith(
            LoadingContactsController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await _openContacts(tester, container, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an error state with a retry action', (tester) async {
      final container = createContainer(
        overrides: [
          contactsControllerProvider.overrideWith(ErrorContactsController.new),
        ],
      );
      addTearDown(container.dispose);
      await _openContacts(tester, container);

      expect(
        find.text('Contacts could not be saved or loaded.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });
  });
}