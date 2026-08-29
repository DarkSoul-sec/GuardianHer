# Phase 3G Report — Communication (user-confirmed cascade)

**Status:** complete · **Tests:** 318 passing (296 baseline + 22 new) · `flutter analyze` clean · debug APK builds.

## What shipped

Every message flow is still **user-confirmed**: we only ever *open a composer or the share sheet*. Nothing sends silently; no `SEND_SMS` permission exists anywhere in the app.

### 1. Delivery cascade (`CascadeCheckInMessageSender`)

Replaces the SMS-only Phase 3D sender for check-ins. Tries, in order, stopping at the first channel that opens:

1. **SMS composer** — `ACTION_SENDTO sms:` with all recipients + body pre-filled.
2. **Email composer** — `mailto:` draft to every selected contact's optional email (skipped when none stored).
3. **System share sheet** — plain text via share_plus; any installed app can take it.

Only when all three fail does it return `CheckInSenderFailure`. Distinct failure types (`NoSmsAppAvailableFailure`, `NoEmailAppAvailableFailure`, `ShareUnavailableFailure`) drive the fallback decisions; any other error aborts immediately.

The same fallback idea was applied to **Location → Share location**: if no SMS app resolves, the pre-filled location message goes to the share sheet.

### 2. SMS URI fixes

- Multi-recipients are joined with `,`, not `;`, and each number gets a `+` prefix — Google/Samsung Messages then parse stored international digits (`919876543210`) as full E.164 addresses instead of local numbers missing the country code.

### 3. Optional contact email

`TrustedContact` gained an optional `email` (trimmed/lower-cased, blank → null), validated by a pragmatic shape check (`local@domain.tld`, ≤254 chars). The add/edit form exposes an "Email (optional)" field; storage stays at document version **1** (old documents without the key load unchanged; a present-but-invalid email is rejected as corrupted data). Passing an empty email on update clears a stored one.

### 4. Manifest package visibility (latent bug fixed)

url_launcher builds `ACTION_SENDTO` intents for `sms:`/`mailto:`, but `<queries>` only declared `VIEW+sms`. On Android 11+ every SMS/email action would have silently failed to resolve. Added `SENDTO` entries for `sms`/`smsto`/`mailto` (kept `VIEW+sms`).

## Play Store policy matrix

| Concern | Status |
| --- | --- |
| SMS / Call Log permissions group | **Not used.** No `SEND_SMS`/`READ_SMS`/`RECEIVE_SMS`; composer-only via `ACTION_SENDTO`. No restricted-permission declaration needed. |
| Silent messaging | Impossible by construction — every send requires a user tap inside a system app. |
| Background location | Not requested. Location capture during SOS uses a location-type foreground service (Phase 3E/3F design); email/share additions do not change it. |
| `queries` elements | Standard intent-based visibility; no contact list scraping. |
| share_plus | System share sheet; no user data leaves the device without explicit user interaction. |

## Files touched (summary)

- `lib/features/check_in/data/cascade_check_in_message_sender.dart` (new; replaces `url_launcher_check_in_message_sender.dart`)
- `lib/features/check_in/domain/check_in_message.dart` (+`recipientEmails`)
- `lib/features/check_in/application/check_in_controller.dart` (resolves numbers + deduped emails)
- `lib/core/platform/email_service.dart`, `share_service.dart` (interfaces) + `lib/data/{email_service_impl,share_service_impl}.dart`
- `lib/core/providers.dart` (bindings) · `check_in_providers.dart` (sender provider)
- `lib/features/location/application/location_controller.dart` (share-sheet fallback)
- Contacts model/validator/repository/controller/form (+optional email)
- `android/app/src/main/AndroidManifest.xml` (`<queries>` SENDTO sms/smsto/mailto)
- Tests: cascade sender (8), validator email rules (5), model email (2), repository email round-trip/corruption/clear (3), controller email resolution (1), location fallback (2) — plus fakes (`FakeShareService` in shared helpers)
