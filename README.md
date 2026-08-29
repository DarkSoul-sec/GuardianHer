# GuardianHer

**GuardianHer** is a personal safety application focused on immediate, reliable emergency assistance. It provides multiple SOS triggers, location sharing, safety check-ins, and incident recording — all designed to work without requiring a backend server for core safety features.

## Core Safety Purpose

GuardianHer helps users quickly alert trusted contacts during emergencies. It prioritizes:

- **Immediate access** — no app lock, PIN, or biometric gate on launch
- **Multiple trigger paths** — large on-screen button, shake detection, Quick Settings tile, home-screen widget
- **Honest communication** — never claims messages were "sent"; only that composers were opened
- **Privacy by default** — no tracking, no analytics, no cloud sync unless explicitly configured
- **Fail-closed behavior** — if something fails, the user is told honestly

---

## SOS Triggers

| Trigger | Description | Requirements |
|---------|-------------|--------------|
| **On-screen button** | Large hold-to-confirm SOS button on Home screen | App open |
| **Shake SOS** | 3 deliberate shakes while app is closed (opt-in) | Android only; `SYSTEM_ALERT_WINDOW` permission for cold launches |
| **Quick Settings Tile** | Tap tile to launch SOS (Android 7+) | Android only |
| **Home Widget** | 1×1 launcher widget opening SOS directly | Android only |

**When SOS activates:**
1. Vibration alert starts (repeating pattern, OS-driven)
2. Foreground location service starts (captures fix while locked/backgrounded)
3. Emergency SMS bridge starts (sends SMS to all guardians via native service)
4. Location capture attempted (one-shot, foreground)
5. Live location sharing session starts (if configured and backend URL provided)
6. Safety Recorder begins recording incident events

**SOS has absolute priority** — it interrupts and closes any active Journey or Check-In.

---

## Shake SOS (Android only, opt-in)

- Runs a foreground service (`specialUse` type) monitoring the accelerometer
- Detects 3 quick shakes within a configurable window (10 s cooldown)
- Launches app with `guardianher://shakesos` URI → arms SOS immediately
- **Critical limitation**: On Android 14+, a cold launch (app fully closed) behind a secure lock screen is **silently refused** by the OS unless the user grants "Display over other apps" (`SYSTEM_ALERT_WINDOW`). The Settings screen checks and links to this permission.
- Without the overlay permission, the shake is detected but the app cannot launch — the user sees nothing.
- Persistent low-priority notification shows while detector runs.
- Survives reboot via `BootReceiver` (restored from native preference flag).
- Battery optimization whitelisting strongly recommended (Redmi/MIUI kills unwhitelisted services).

---

## Quick Settings SOS Tile (Android 7+, opt-in)

- Pure trigger: tap launches `guardianher://tilesos` → existing SOS pipeline arms
- **Locked-screen behavior**: Works when Flutter process is alive; cold launch behind secure keyguard is refused (same as Shake SOS). Tile service uses `unlockAndRun` to prompt unlock.
- Tile state mirrors SOS engagement (Dart → Kotlin via MethodChannel); may show stale "engaged" after force-stop/crash until app reopens.

---

## Home Widget (Android only)

- 1×1 launcher widget; tap opens app with `guardianher://sos` URI
- Pure launcher — no background logic, no location capture
- Routes both cold and warm launches to `/sos`

---

## Location Functionality

- **One-shot foreground capture only** — no background location, no continuous tracking
- Uses GMS-free `LocationManager` (GPS + NETWORK providers) — F-Droid compatible
- SOS captures location while phone is locked/screen off via `SosLocationService` (location-type foreground service)
- **Auto-retry**: One retry (15 s) on `unavailable`, `timeout`, or `servicesDisabled` — never on `denied`
- **7 truthful SOS location states**: loading / captured / stale ("Last known location") / servicesDisabled / denied / timeout / unavailable
- **WhatsApp targeting**: `PhoneNumber.toWhatsAppDigits()` canonicalizes to bare international digits; deep link uses `whatsapp://send?phone=&text=` (not wa.me) so unavailable surfaces as error, not silent browser open
- **Coordinate-free session snapshot**: While SOS active, state/capture-time/accuracy/failure-category written to prefs (no lat/lng, URLs, contacts) — cleared on cancel/idle and at boot

---

## Live Location Sharing (Opt-in, Off by Default)

- **Requires `--dart-define=GUARDIANHER_LIVE_API_URL=https://…`** at build time; empty = feature disabled
- **Backend** (separate, optional): FastAPI + SQLAlchemy; stores only token hash + latest point; purges on expire/revoke
- **Sessions**: Explicit user start OR active SOS only; no boot restore, no silent resume
- **Token**: 43-char `secrets.token_urlsafe(32)`; server stores SHA-256 hex digest only
- **Public page**: Vanilla JS + OSM raster tiles (`tile.openstreetmap.org`); CSP pinned; polling (5 s); no SSE/WebSocket
- **Android**: New location-type FGS (`LiveLocationService.kt`), `START_NOT_STICKY` — separate from SOS location service
- **Engine**: `startLiveUpdates`/`stopLiveUpdates` streaming fixes over EventChannel `guardianher/location_updates`
- **Client lifecycle**: In-memory only; process death = interrupted; offline capture continues with "Connection unavailable" status
- **SOS integration**: Emergency live session starts automatically (10 s cadence, 60 min duration); failure never blocks SOS; share URL appended to SOS message only when available

---

## Safe Journey

- Wraps shared `SafetySession` ledger (`type: safe_journey`)
- Delegates ALL tracking to LiveLocation machinery (120 min / 30 s interval)
- **Escalation = transformation**: When SOS engages during active journey, journey's own share closes, then `live.startEmergency()` called — exactly ONE emergency share results
- Ledger records `JourneyEndReason.escalatedToSos`; no auto-resume after emergency
- Start refused while SOS active; duplicate starts absorbed
- **Vehicle info** (optional, in-memory only): `VehicleType` {auto, taxi, cab, bus, privateVehicle, other} + registration/driver/booking (never persisted, never logged, never in URLs)
- Share messages use system share sheet + clipboard only; wording describes what user chose to share + expiry, never claims monitoring

---

## Vehicle Information (In-Memory Only)

- `VehicleType` closed enum with friendly labels
- Registration normalization: canonicalizes recognized Indian formats (DL01AB1234, BH-series); unrecognized plates pass through verbatim
- Optional fields: registrationNumber, driverName, bookingReference (clamped to 60 chars)
- Emergency vehicle context bridge: published at journey start, survives SOS escalation, released when SOS settles
- Share bodies include vehicle label + spaced registration ONLY when explicitly passed; driver/booking NEVER included

---

## Safety Recorder

- Single `SafetyRecorderController` (Riverpod Notifier) observes all feature providers
- Rolling in-memory buffer (max 500 events, 10 min window) → frozen into `SafetyIncident` on SOS activation
- Event types (closed enum): shakeDetected, sosActivated, sosCancellationStarted, sosCompleted, locationCaptureStarted, locationCaptured, locationUnavailable, locationTimeout, locationPermissionDenied, locationServicesDisabled, locationUpdated, communicationAttempted, communicationFailed, communicationHandedOff, journeyStarted, journeyEnded, vehicleAttached, sessionStarted, sessionCompleted, sessionExpired, checkInStarted, checkInCompleted
- Metadata via string constants only (no nested objects): `vehicleType`, `hasRegistration`, `accuracyMeters`, `isStale`, `failureCategory`, `channelType`, `endReason`
- Hash chain: SHA-256 from genesis `guardianher-recorder:v1`; binds `eventId + eventType + occurredAt`; metadata NOT in chain
- Repository: SharedPreferences-backed JSON; max 20 incidents; single eviction point
- **Privacy**: NO coordinates, phone numbers, emails, message bodies, vehicle registrations, or PII in any event
- Shake integration: `shakeDetected` recorded in `onEmergencyTrigger` callback (before `startSos()`), only for `guardianher://shakesos` URIs
- Failure isolation: Recorder exceptions caught/logged; never block safety features

---

## Safety Check-In

- **Scheduled reminders** at user-chosen interval {60, 120, 180 min}
- User confirms "I am safe" → one-shot foreground location capture → user-confirmed message composer cascade (SMS → email → share sheet)
- **No auto-send**, no `SEND_SMS`, no foreground service, no background location
- Location failure never cancels check-in — message composed with "could not share my location"
- Missed check-ins escalate (re-notify + urgency wording) via pure functions
- Settings persist via `PreferencesCheckInSettingsRepository` (recipients as contact IDs)
- **Phase 3H-3**: Scheduled fire EXECUTES pipeline (not just reminder): `runScheduledCheckIn` runs from main isolate AND background isolate (`handleSafetyCheckInBackground` @pragma vm:entry-point)
- Background dispatch via `localNotificationsBackgroundTrampoline` (flutter_local_notifications requirement)
- Honest status model: captured / stale-only / unavailable / permissionDenied / servicesDisabled / timeout / communicationFailed / schedulerFailed / skippedForSos
- SOS absolute priority: active SOS → `skippedForSos` + reschedule; never delays/cancels SOS
- **Alarm limitation**: `onDidReceiveBackgroundNotificationResponse` only fires for user taps, not scheduled deliveries. Pipeline completes on notification tap → `CheckInScreen` auto-runs `runDueCheckIn` once per entry.
- **Cold tap dispatch**: `ensureLocalNotificationsInitialized` queries `getNotificationAppLaunchDetails` and dispatches tap handler at startup
- **Force-stop healing**: `refresh()` always re-asserts `scheduleExecution` (idempotent id-2001 upsert)

---

## Communication Fallback (Phase 3G)

- **User-confirmed cascade only** — no auto-send, no `SEND_SMS` in primary path
- Channels: SMS composer → email composer (if contact has email) → system share sheet
- Each channel's failure type drives next step; wording stays "opened", never "sent"
- Multi-recipient SMS URIs join with `,` and prefix every number with `+` (E.164)
- Contacts carry OPTIONAL normalized email (document version 1; empty update clears it)
- Manifest `<queries>` includes `SENDTO` sms/smsto/mailto + WhatsApp packages — required for Android 11+ visibility
- WhatsApp deep link uses `whatsapp://send?phone=&text=` scheme; failure opens dialog with [Send via SMS] + [Share another way]

---

## Privacy Philosophy

- **No tracking, no analytics, no cloud sync by default**
- **Location**: One-shot foreground only; never continuous; never background
- **Contacts**: Stored locally in Keystore-backed secure storage (digits-only E.164)
- **Live location**: Opt-in, explicit start, token in memory only, server stores hash only
- **Vehicle info**: In-memory only, never persisted, never logged
- **Safety Recorder**: No PII in events; hash chain for integrity, not encryption
- **Delete-all-data**: `DataCleanupService.deleteAllLocalData()` wipes secure storage + preferences
- **Logs**: Token-shaped segments and coordinate pairs redacted by `PrivacyFilter` before any log line exists (backend)
- **Third-party**: OSM tiles only (`tile.openstreetmap.org`); no Firebase, no GMS for core features, no proprietary SDKs

---

## F-Droid Goal

GuardianHer targets F-Droid inclusion. Known considerations:

| Concern | Status |
|---------|--------|
| **Google Play Services** | LiveSharingService uses `com.google.android.gms.location.FusedLocationProviderClient` — this is a proprietary dependency. Core SOS/Location/Check-In use GMS-free `LocationManager`. |
| **Firebase** | None |
| **Proprietary SDKs** | None (http, share_plus, url_launcher, flutter_local_notifications, vibration, home_widget, permission_handler, telephony, timezone, flutter_timezone, flutter_secure_storage, shared_preferences, flutter_riverpod, go_router — all open-source) |
| **Tracking/Analytics** | None |
| **Reproducible Build** | Version from pubspec.yaml; all deps from pub.dev |
| **Source Completeness** | All source in repo; backend in `backend/` |

**The `LiveSharingService` GMS dependency is the primary F-Droid blocker.** Options: (1) Replace with `LocationManager` (like core location), (2) Make live-sharing a build-time flavor excluding the service, (3) Accept as optional non-F-Droid flavor.

---

## Optional Backend Functionality

The live-location sharing feature requires a separate backend service (`backend/`). It is **completely optional** — the app builds and runs all core safety features (SOS, Shake SOS, Check-In, Journey, Safety Recorder, Location) without it.

Backend deployment:
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --port 8080
```

Configure with environment variables:
- `GUARDIANHER_DATABASE_URL` (default: SQLite)
- `GUARDIANHER_BASE_URL` (public origin for share URLs)
- `GUARDIANHER_REQUIRE_HTTPS` (enforce TLS)
- `GUARDIANHER_MAX_SESSION_MINUTES` (server-side ceiling)
- `GUARDIANHER_SWEEPER_SECONDS` (expiry sweeper interval)

App build with backend:
```bash
flutter build apk --dart-define=GUARDIANHER_LIVE_API_URL=https://your-backend.example.org
```

---

## Installation / Build Instructions

### Prerequisites
- Flutter SDK ^3.13.0 (Flutter 3.18+)
- Android SDK: platforms 34, 35, 36; build-tools 36.0.0; NDK 28.2.13676358; CMake 3.22.1
- JDK 17
- Python 3.10+ (for backend)

### Debug Build
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

### Release Build (Unsigned)
```bash
flutter build apk --release
# Uses debug signing config — configure release keystore in android/app/build.gradle.kts for distribution
```

### With Live Location Backend
```bash
flutter build apk --release --dart-define=GUARDIANHER_LIVE_API_URL=https://your-backend.example.org
```

### Run Backend Tests
```bash
cd backend
python -m pytest tests -q
```

---

## Known Limitations (Honest Disclosure)

- **No guaranteed emergency delivery** — SMS/email/share depend on user action and system apps
- **No guaranteed GPS accuracy** — depends on device, environment, satellite visibility
- **No guaranteed WhatsApp/SMS delivery** — opens composers only
- **No guaranteed background execution** — Android OEM battery optimizations may kill services
- **No legal evidence** — Safety Recorder provides tamper-evident hash chain, not tamper-proof legal proof
- **No invisible tracking** — all features are user-initiated and visible
- **Shake SOS cold launch** requires `SYSTEM_ALERT_WINDOW` permission on Android 14+ behind lock screen
- **Live location sharing** requires optional backend and `GUARDIANHER_LIVE_API_URL` build define
- **Check-in reminders** use inexact alarms (may drift a few minutes)
- **Force-stop** cancels alarms; healed on next app open

---

## Project Structure

```
lib/
  app/                    # App shell, router, theme, home screen
  core/                   # Platform interfaces, providers, security, routing
  features/
    check_in/             # Safety check-in (domain, application, data, presentation)
    contacts/             # Trusted contacts management
    journey/              # Safe Journey (wraps SafetySession + LiveLocation)
    live_location/        # Real-time live location sharing
    location/             # One-shot location capture + share
    onboarding/           # First-run flow
    safety_recorder/      # Incident event recording + integrity
    safety_session/       # Shared session ledger (SOS/Journey/CheckIn)
    settings/             # App settings (privacy, device admin, shake SOS)
    shake/                # Shake SOS detection
    sos/                  # SOS flow (state machine, orchestration, UI)
  shared/                 # Premium UI components, AppShell
  main.dart               # Entrypoint + notification routing
test/                     # Widget/unit tests + shared fakes
android/                  # Android platform code (Kotlin services, receivers)
ios/                      # iOS platform scaffolding
backend/                  # Optional FastAPI live-location backend
docs/                     # Phase reports
assets/brand/logo.png     # App icon source
```

---

## Version

Current: **1.0.0+1** (see `pubspec.yaml`)

---

## License

**LICENSE decision required before public publication.** See [SECURITY.md](SECURITY.md) for vulnerability reporting.