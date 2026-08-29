# Phase 3B Completion Report — Emergency Actions

## 1. Scope and Goal
Phase 3B delivered the "Emergency Actions" layer: a bounded one-shot SOS vibration, a best-effort Android notification that never cancels or blocks SOS, an explicit user-driven phone dialer and SMS composer, plus the coordinator logic that wires these into the existing SOS state machine. All changes follow the approved plan and the user's security corrections: **no automatic calls/messages** (explicit Call/Message buttons only), **notification/vibration failure never affects the SOS state**, vibration **auto-stops and never loops**, and all UI copy is truthful ("Dialer opened." not "Call completed.").

## 2. What Was Built

### Data layer (`lib/data/`)
| File | Contents |
|---|---|
| `call_service_impl.dart` | `UrlLauncherCallService` — launches `tel:` via `url_launcher`; `buildDialUri(number)` builds a `tel:+E164` URI (E.164 normalization + `+` prefix). |
| `sms_service_impl.dart` | `UrlLauncherSmsService` — launches `sms:` via `url_launcher`; `buildSmsUri(number, body)` builds `sms:+E164?body=<encoded>` (query-parameter form). |
| `vibration_service_impl.dart` | `VibrationServiceVibration` — bounded, non-repeating one-shot: `sosVibrationPattern = [0, 300, 200, 300, 200, 300]`, `sosVibrationRepeat = -1` (must never loop). |
| `notification_service_impl.dart` | `FlutterLocalNotificationsNotificationService` — Android-only, lazily initialized; channel `sos_alert` / "SOS alerts", id `1001`, `ongoing`, `autoCancel: false`, `onlyAlertOnce`, no sound/vibration, `visibility: public`, category `service`; **generic content** (no digits — enforced by test): "SOS ACTIVE" / "Open GuardianHer to manage your SOS." and "SOS" / "Stopping SOS…". Exposes `onNotificationTap` callback. |

### Core layer
- `lib/core/error/failures.dart` — new failures: `NoDialerAvailableFailure`, `NoSmsAppAvailableFailure`, `NotificationPermissionDeniedFailure`, `VibrationUnavailableFailure`, `PlatformActionFailure`.
- `lib/core/providers.dart` — `callServiceProvider`, `smsServiceProvider`, `notificationServiceProvider`, `vibrationServiceProvider` now resolve to the concrete impls.
- `lib/main.dart` — notification tap navigates to `/sos` via a `ProviderScope` override of the notification provider (`ref.read(appRouterProvider).go(AppRoutes.sos)`), keeping the core layer free of router imports.

### Application layer (`lib/features/sos/application/`)
- `sos_actions_state.dart` — `SosNotificationStatus {unknown, active, stopping, unavailable}`, `SosVibrationStatus {idle, active, failed}`, `SosNotificationPermission {unknown, granted, denied}`, `SosActionKind {callContact, messageContact, callEmergency}`, `SosActionOutcome` (success/failure with `isSuccess`, `message`), `SosActionsState` (`copyWith` + `statusFragments`).
- `sos_action_controller.dart` — `SosActionController extends Notifier<SosActionsState>`, wired via `ref.listen(sosControllerProvider)`:
  - **Arming**: requests notification permission once per session (reset on idle).
  - **Active**: plays the bounded vibration; shows the notification only if permission granted — any failure degrades to status only, SOS stays active.
  - **Cancelling**: stops vibration; shows "Stopping SOS…".
  - **Completed/Idle**: cancels notification; stops vibration; resets permission gating.
  - **User actions**: `callContact`/`messageContact` (E.164-normalized) and `callEmergency` (digits-only, non-empty — deliberately not `PhoneNumber.isValid`, which rejects `112`). Outcomes are truthful (`_toOutcome`).
- `sos_providers.dart` — added `sosEmergencyNumberProvider` (`'112'`), `sosSmsBodyProvider` (generic body), `sosActionsControllerProvider`.

### Presentation (`lib/features/sos/presentation/sos_screen.dart`)
ACTIVE view upgraded: status line (vibration / notification / permission states), contacts section with **masked numbers** (`_maskPhone`) and Call/Message tooltip buttons, "Call emergency" outlined button, "End SOS" filled button, and `SnackBar` outcomes from `_runAction`. Contacts are never auto-called.

## 3. Behavior Guarantees (binding)
1. Notification/vibration failure **never** cancels or blocks SOS — SOS stays ACTIVE; status shows "Notifications unavailable — SOS remains active."
2. Activation never dials or messages anyone automatically.
3. Vibration is bounded, auto-stopped, non-looping (`repeat: -1`), asserted against the real `vibration` package API.
4. Contact numbers are masked in UI; no logs of names/numbers/bodies.
5. Truthful copy only — never "Call completed." / "SMS sent." / "Contact notified."

## 4. Tests
- `test/features/sos/sos_test_fakes.dart` — added `FakeVibrationService`, `FakeNotificationService`, `FakeCallService`, `FakeSmsService`; `createSosContainer` overrides the 4 service providers.
- `test/data/vibration_service_test.dart` — asserts exact SOS pattern + `repeat == -1` via a `RecordingVibrationPlatform` (`extends VibrationPlatform`), no-vibrator error path, stop.
- `test/data/emergency_platform_services_test.dart` — dial/SMS URI builders, notification constants, and a **no-digit-in-copy guard**.
- `test/features/sos/sos_action_controller_test.dart` — full lifecycle (permission once per session, vibration+notification on active, stop/stopping on cancel, reset on idle, re-request next session), denied permission leaves SOS active, permission-request failure, vibration failure, re-activation guard, user actions (normalized number, generic body, 112, invalid contact rejected, invalid emergency number, truthful failure).
- `test/features/sos/sos_screen_actions_test.dart` — widget tests: masked contacts, Call/Message/Call-emergency taps, denied-permission status line, empty-contacts message.
- `test/core/providers_test.dart` — updated for the newly resolved providers.

**Result:** `flutter analyze` — no issues; `flutter test` — **247/247 passing** (218 baseline + 29 new).

## 5. Android Build (verified)
- **`flutter build apk --debug` succeeds**: `build/app/outputs/flutter-apk/app-debug.apk`.
- Environment constraint discovered: AGP 9.1.0 / sdklib 32.1.0 cannot resolve `android-37` (API 37 platforms hash to `android-37.0`; there is no special-case for 37 in `AndroidVersion.getPlatformHashString`). Per the approved decision the project stays on **compileSdk 36**:
  - `permission_handler` pinned `^12.0.0` (permission_handler_android 14 from 13.x needs API 37).
  - `flutter_secure_storage` kept on 11.x, forced to `compileSdk = 36` via the `afterEvaluate` hook in `android/build.gradle.kts` (it hardcodes 37).
  - Installed the genuine platforms the plugins need: `platforms;android-34`, `platforms;android-35`, `platforms;android-36`, `cmake;3.22.1` (all documented in `AGENTS.md`).
  - All temporary SDK-37 hacks (hand-made `android-37` dir, mislabeled `android-37.0`) were removed; the SDK now contains only genuine packages.
- Note: no device/emulator is attached, so runtime behavior is covered by unit/widget tests, not on-device verification.

## 6. Status
Phase 3B is complete. No automatic calls/messages, no notification blocking, no data collection, no location/GPS/camera/microphone/Firebase/backend/history. Per plan, Phase 3C is NOT started.