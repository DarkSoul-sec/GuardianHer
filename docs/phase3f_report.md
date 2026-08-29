# Phase 3F Completion Report — Background Safety Agent

## 1. Scope and Goal
Phase 3F made GuardianHer's background story real and policy-compliant. The Shake SOS detector (the "background safety agent", Phase 3E) already ran as a `specialUse` foreground service, but three genuine gaps remained: **scheduled check-in reminders could never fire on a real device** (flutter_local_notifications ≥ 16 no longer merges its alarm/boot receivers — the app must declare them), **the detector died permanently on reboot** until the user happened to open the app, and **battery/OEM guidance was a blind link with no status feedback**. Everything stays user-opt-in: no new tracking, no background location, no auto-send.

## 2. What Was Built

### Android manifest (`android/app/src/main/AndroidManifest.xml`)
| Change | Purpose |
|---|---|
| `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>` | Normal install-time permission; lets the plugin re-register reminder alarms after reboot/update and our receiver restore the shake detector. |
| `com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver` (exported=false) | **Fixes a latent bug:** alarm PendingIntents target this component; without it in the manifest no `zonedSchedule` reminder could ever fire on device. |
| `com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver` (exported=false) + BOOT_COMPLETED / MY_PACKAGE_REPLACED / QUICKBOOT_POWERON (+ HTC variant) | Re-registers every scheduled reminder after reboot / app update. |
| `.BootReceiver` (exported=false) | Restores the Shake SOS detector after reboot / quick boot / app update. |
| Comment block documenting deliberately-not-requested permissions | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Play-restricted; we link to settings instead) and `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` (reminders stay `inexactAllowWhileIdle`, may drift minutes). |

System broadcasts (BOOT_COMPLETED etc.) are protected — only the OS can send them — so exported=false receivers still receive them and third-party apps cannot spoof a wake-up.

### Native code (Kotlin)
- **`BootReceiver.kt`** (new): on boot / quick-boot / package-replaced, starts `ShakeSosService` **only if the user enabled it**, wrapped in try/catch. Field reports show some Android 16 builds throw `ForegroundServiceStartNotAllowedException` for `specialUse` FGS launches from `BOOT_COMPLETED` even though that type is not on Google's documented restriction list (dataSync/camera/mediaPlayback/phoneCall/mediaProjection/microphone); aggressive OEM managers kill them too. A refusal logs and falls back to the existing Dart-side re-anchor when the app next opens. Never touches `SosLocationService` (no SOS session survives a restart).
- **`ShakeSosService.kt`**: companion gains `setUserEnabled`/`isUserEnabled` backed by an app-private prefs file (`guardianher_background`) so the receiver needs no Flutter engine.
- **`MainActivity.kt`**: the `guardianher/shake_sos` channel records the flag on user-driven `start`/`stop` only (internal re-anchors don't touch it), and adds:
  - `isIgnoringBatteryOptimizations` → `PowerManager.isIgnoringBatteryOptimizations(packageName)`;
  - `manufacturerToken` → normalized token (`miui` covers Xiaomi/Redmi/POCO, `coloros` Oppo/OnePlus/realme, `funtouch` Vivo/iQOO, `emui`, `magicos`, `samsung`; null otherwise).

### Dart
- `lib/core/platform/shake_sos_service.dart` — interface/channel gain the two methods above.
- `lib/features/shake/domain/oem_background_guidance.dart` (new) — pure token→guidance mapping (MIUI Autostart trap, Samsung Sleeping apps, etc.), unit-tested.
- `lib/features/shake/presentation/shake_sos_settings_screen.dart` — battery tile now shows **live status** ("Allowed to run in the background…" vs "Not protected yet…"), plus OEM-specific hint line; both refresh on lifecycle resume like the overlay tile; enabled-state copy now mentions automatic restart after reboot/updates.
- `test/helpers/fakes.dart` + per-file fakes updated for the extended interface.

## 3. Behavior Guarantees (binding)
1. Boot restore is **opt-in state only**: nothing runs after reboot unless the user enabled Shake SOS; no SOS session or location capture is ever started from a receiver.
2. Receiver refusals never crash — logged, then Dart-side restore covers the next app open.
3. Battery guidance uses only the system settings page — the restricted direct-request intent/permission is not used (Play-policy compliance).
4. Reminders remain `inexactAllowWhileIdle`; no exact-alarm permission is requested.
5. No new sensitive data; the native flag stores one boolean.

## 4. Tests & Verification
- New: 5 widget tests on the Shake SOS screen (battery warning/link, exempt status, MIUI hint, Samsung hint, stock-Android absence of hints) + 8 unit tests for the OEM mapping (`test/features/shake/oem_background_guidance_test.dart`).
- Fakes updated everywhere the interface grew (`test/helpers/fakes.dart`, sos_test_fakes, controller/screen test fakes).
- **Result:** `flutter analyze` — no issues; `flutter test` — **296/296 passing**; `flutter build apk --debug` succeeds; merged debug manifest confirmed to contain all four receivers + permission.
- On-device follow-ups (Redmi target): reboot with detector enabled → notification returns without opening the app; toggle off → reboot → service stays down; schedule a check-in reminder → reboot → alarm still fires.

## 5. Status
Phase 3F is complete. The background safety agent now survives reboot/app-update, users can see and fix why it might be killed, and the whole surface stays within Android policy: typed foreground services only where genuinely required (shake detection = specialUse; SOS location hold = location), opt-in receivers on protected broadcasts, and no restricted permissions.
