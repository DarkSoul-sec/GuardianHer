import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/application/contacts_state.dart';
import '../../contacts/domain/phone_number.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../application/location_providers.dart';
import '../domain/location_point.dart';

/// Shows the trusted-contact picker and opens a pre-filled WhatsApp chat for
/// the chosen contact.
///
/// Flow contract (Phase 3I):
///
/// * one tap performs exactly ONE launch attempt — there is no automatic
///   retry loop over multiple contacts;
/// * success only means "WhatsApp was opened" — nothing is claimed about the
///   recipient's registration or about anything being sent;
/// * when WhatsApp cannot be opened at all, an explicit fallback dialog offers
///   [Send via SMS] (composer, still user-sent) and [Share another way]
///   (system share sheet).
Future<void> showWhatsAppShareFlow(
  BuildContext context,
  WidgetRef ref,
  LocationPoint point,
) async {
  final contactsState = ref.read(contactsControllerProvider);
  final contacts = switch (contactsState) {
    ContactsLoaded(:final contacts) => contacts,
    _ => const <TrustedContact>[],
  };
  if (contacts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No trusted contacts yet. Add one in the Contacts tab to share '
          'directly.',
        ),
      ),
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final contact = await showModalBottomSheet<TrustedContact>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Share with a trusted contact'),
          ),
          for (final contact in contacts)
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(contact.name),
              subtitle: Text(_maskPhone(contact.phoneNumber)),
              onTap: () => Navigator.of(sheetContext).pop(contact),
            ),
        ],
      ),
    ),
  );
  if (contact == null || !context.mounted) {
    return;
  }

  final result =
      await ref.read(locationControllerProvider.notifier).shareViaWhatsApp(
            contact,
          );

  switch (result) {
    case Ok():
      messenger.showSnackBar(
        const SnackBar(content: Text('WhatsApp chat opened.')),
      );
    case Err(:final failure):
      if (!context.mounted) return;
      await _showFallbackDialog(context, ref, contact, point, failure);
  }
}

/// Graceful failure for a WhatsApp chat that could not be opened.
///
/// The wording never claims WHY the number failed on WhatsApp's side (the app
/// cannot know registration state) — it only states what GuardianHer observed
/// and immediately offers the two alternative channels.
Future<void> _showFallbackDialog(
  BuildContext context,
  WidgetRef ref,
  TrustedContact contact,
  LocationPoint point,
  Failure failure,
) async {
  final message = ref.read(locationShareMessageProvider)(point);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("WhatsApp isn't available for this contact."),
      content: Text(failure.message),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            ref.read(smsServiceProvider).openComposer(
                  phoneNumber: PhoneNumber.normalize(contact.phoneNumber),
                  body: message,
                );
          },
          child: const Text('Send via SMS'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            ref.read(shareServiceProvider).shareText(message);
          },
          child: const Text('Share another way'),
        ),
      ],
    ),
  );
}

/// Masks all but the last four digits so the picker is safe to glance at.
String _maskPhone(String digits) {
  if (digits.length <= 4) {
    return digits;
  }
  final tail = digits.substring(digits.length - 4);
  return '${List.filled(digits.length - 4, '•').join()}$tail';
}
