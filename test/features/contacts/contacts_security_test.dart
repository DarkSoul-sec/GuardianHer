import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/data/secure_storage_app_lock_repository.dart';
import 'package:guardianher/features/auth/presentation/lock_screen.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/data/contacts_repository_impl.dart';
import 'package:guardianher/features/contacts/domain/contact_failures.dart';
import 'package:guardianher/features/contacts/presentation/contacts_screen.dart';

import '../../helpers/fakes.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const GuardianHerApp(),
  );
}

/// Container whose app lock is locked (a PIN is stored but not unlocked).
Future<ProviderContainer> _lockedContainer() async {
  final storage = FakeSecureStorageService();
  final stored = await TestPinHasher().hashPin('123456');
  await storage.write(AppLockStorageKeys.pin, stored.encode());
  return ProviderContainer(
    overrides: [
      ...defaultOverrides(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      ),
      pinHasherProvider.overrideWithValue(TestPinHasher()),
    ],
  );
}

void main() {
  group('contacts security', () {
    testWidgets(
        'contacts routes redirect to the lock screen while the app is locked',
        (tester) async {
      final container = await _lockedContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);

      for (final route in [
        AppRoutes.contacts,
        AppRoutes.contactsAdd,
        AppRoutes.contactsEdit('any'),
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          find.byType(LockScreen),
          findsOneWidget,
          reason: '$route must redirect to the lock screen while locked',
        );
        expect(
          find.byType(ContactsScreen),
          findsNothing,
          reason: '$route must not reach contacts while locked',
        );
      }
    });

    testWidgets('contacts are reachable after unlocking', (tester) async {
      final container = await _lockedContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      router.go(AppRoutes.contacts);
      await tester.pumpAndSettle();

      expect(find.byType(ContactsScreen), findsOneWidget);
    });

    test('failure messages never leak phone numbers', () {
      const failures = <Failure>[
        DuplicateContactFailure(),
        MaxContactsReachedFailure(),
        ContactNotFoundFailure(),
        CorruptedContactDataFailure(),
        SerializationFailure(),
        ContactStorageFailure(),
      ];
      for (final failure in failures) {
        expect(
          failure.message,
          isNot(contains(RegExp(r'\d{7,}'))),
          reason: '${failure.runtimeType} must not embed phone numbers',
        );
      }
    });

    test('contacts are persisted through secure storage only', () async {
      final storage = FakeSecureStorageService();
      final preferences = FakePreferencesService();
      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          preferencesServiceProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(contactsControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final result = await controller.addContact(
        name: 'Mom',
        phoneNumber: '+911234567890',
      );
      expect(result, isA<Ok<void>>());
      await container.pump();

      expect(await storage.containsKey(ContactsStorageKeys.contacts), isTrue);
      expect(
        await storage.read(ContactsStorageKeys.contacts),
        contains('911234567890'),
      );
      // SharedPreferences must never hold contact data.
      expect(preferences.getKeys(), isEmpty);
    });
  });
}