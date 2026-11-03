import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/platform/email_service.dart';
import 'package:guardianher/core/platform/share_service.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/check_in/data/cascade_check_in_message_sender.dart';
import 'package:guardianher/features/check_in/domain/check_in_failures.dart';
import 'package:guardianher/features/check_in/domain/check_in_message.dart';

class FakeEmailService implements EmailService {
  final List<({List<String> addresses, String subject, String body})> calls =
      [];
  bool unavailable = false;

  @override
  Future<Result<void>> compose({
    required List<String> addresses,
    required String subject,
    required String body,
  }) async {
    calls.add((addresses: addresses, subject: subject, body: body));
    if (unavailable) {
      return const Err(NoEmailAppAvailableFailure());
    }
    return const Ok(null);
  }
}

class FakeShareService implements ShareService {
  final List<String> shared = [];
  bool unavailable = false;

  @override
  Future<Result<void>> shareText(String text) async {
    if (unavailable) {
      return const Err(ShareUnavailableFailure());
    }
    shared.add(text);
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareFile(String filePath) async {
    if (unavailable) {
      return const Err(ShareUnavailableFailure());
    }
    shared.add(filePath);
    return const Ok(null);
  }
}

void main() {
  const body = 'I am safe. https://maps.google.com/?q=1,2';

  CheckInMessage message({
    List<String> numbers = const ['919876543210'],
    List<String> emails = const [],
  }) {
    return CheckInMessage(
      recipientPhoneNumbers: numbers,
      recipientEmails: emails,
      body: body,
      missedCount: 0,
      composedAt: DateTime.utc(2026),
    );
  }

  group('buildCheckInSmsUri', () {
    test('prefixes every number with + and joins with commas', () {
      final uri = buildCheckInSmsUri(
        ['919876543210', '447700900123'],
        body,
      );
      expect(uri.scheme, 'sms');
      expect(uri.path, '+919876543210,+447700900123');
      expect(uri.queryParameters['body'], body);
    });

    test('single recipient still carries the + prefix', () {
      final uri = buildCheckInSmsUri(['919876543210'], body);
      expect(uri.path, '+919876543210');
    });

    test('empty recipients produce a body-only URI', () {
      final uri = buildCheckInSmsUri([], body);
      expect(uri.path, isEmpty);
      expect(uri.queryParameters['body'], body);
    });
  });

  group('CascadeCheckInMessageSender', () {
    test('uses the SMS composer when it opens', () async {
      final opened = <Uri>[];
      final email = FakeEmailService();
      final share = FakeShareService();
      final sender = CascadeCheckInMessageSender(
        email: email,
        share: share,
        openSms: (uri) async {
          opened.add(uri);
          return const Ok(null);
        },
      );

      final result = await sender.send(message(emails: ['a@b.co']));

      expect(result, isA<Ok<void>>());
      expect(opened, hasLength(1));
      expect(email.calls, isEmpty);
      expect(share.shared, isEmpty);
    });

    test('falls back to email when no SMS app resolves', () async {
      var smsAttempts = 0;
      final email = FakeEmailService();
      final share = FakeShareService();
      final sender = CascadeCheckInMessageSender(
        email: email,
        share: share,
        openSms: (_) async {
          smsAttempts++;
          return const Err(NoSmsAppAvailableFailure());
        },
      );

      final result = await sender.send(
        message(emails: ['anita@example.com']),
      );

      expect(result, isA<Ok<void>>());
      expect(smsAttempts, 1);
      expect(email.calls, hasLength(1));
      expect(email.calls.single.addresses, ['anita@example.com']);
      expect(email.calls.single.body, body);
      expect(share.shared, isEmpty);
    });

    test('falls back to the share sheet when SMS and email both fail',
        () async {
      final email = FakeEmailService()..unavailable = true;
      final share = FakeShareService();
      final sender = CascadeCheckInMessageSender(
        email: email,
        share: share,
        openSms: (_) async => const Err(NoSmsAppAvailableFailure()),
      );

      final result = await sender.send(
        message(emails: ['anita@example.com']),
      );

      expect(result, isA<Ok<void>>());
      expect(share.shared, [body]);
    });

    test('skips the email channel when no contact has an address', () async {
      final email = FakeEmailService();
      final share = FakeShareService();
      final sender = CascadeCheckInMessageSender(
        email: email,
        share: share,
        openSms: (_) async => const Err(NoSmsAppAvailableFailure()),
      );

      await sender.send(message());

      expect(email.calls, isEmpty);
      expect(share.shared, [body]);
    });

    test('fails with CheckInSenderFailure when every channel is unavailable',
        () async {
      final email = FakeEmailService()..unavailable = true;
      final share = FakeShareService()..unavailable = true;
      final sender = CascadeCheckInMessageSender(
        email: email,
        share: share,
        openSms: (_) async => const Err(NoSmsAppAvailableFailure()),
      );

      final result = await sender.send(message());

      expect(result, isA<Err<void>>());
      expect((result as Err).failure, isA<CheckInSenderFailure>());
    });
  });
}
