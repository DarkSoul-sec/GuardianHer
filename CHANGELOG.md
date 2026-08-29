# Changelog

All notable changes to GuardianHer are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-29

### Added
- **SOS Core**: Multi-trigger SOS (on-screen button, hold-to-confirm), vibration alert (OS-driven repeating pattern), emergency SMS bridge (native foreground service), one-shot foreground location capture with auto-retry
- **Shake SOS** (Phase 3E): Accelerometer-based detection (3 deliberate shakes), foreground service with persistent notification, `BootReceiver` for reboot survival, `SYSTEM_ALERT_WINDOW` check for cold-launch exemption
- **Quick Settings SOS Tile** (Phase B): Pure trigger launching existing SOS pipeline, locked-screen unlock handling, tile state mirror
- **Home Widget** (Android): 1×1 launcher widget opening SOS directly
- **Safety Check-In** (Phase 3D, 3H-3): Scheduled reminders {60, 120, 180 min}, user-confirmed "I am safe" flow, one-shot location capture, cascade composer (SMS → email → share sheet), missed escalation, background execution via notification tap, force-stop healing
- **Live Location Sharing** (Phase 3J): Opt-in real-time sharing, FastAPI backend (token hash only, OSM tiles, polling), Android location-type FGS, SOS integration (auto emergency session), in-memory client lifecycle
- **Safe Journey** (Phase C): Wraps SafetySession ledger, delegates tracking to LiveLocation (120 min / 30 s), SOS escalation = transformation (closes journey share, starts emergency share), vehicle info (in-memory only)
- **Vehicle Information** (Phase D): `VehicleType` enum, registration normalization (Indian formats + verbatim passthrough), emergency context bridge surviving SOS escalation
- **Safety Recorder** (Phase E): Rolling event buffer (500 events / 10 min), frozen on SOS activation, SHA-256 hash chain from genesis, 20-incident retention, privacy-safe metadata (no PII), observes all feature providers
- **Communication Fallback** (Phase 3G): User-confirmed cascade (SMS → email → share sheet), WhatsApp targeting with `whatsapp://send`, honest "opened" wording, E.164 multi-recipient URIs
- **Trusted Contacts**: Digits-only E.164 storage, country code default +91, optional normalized email
- **Device Administrator** (opt-in): Blocks uninstall/force-stop, no policies declared
- **Privacy**: `DataCleanupService.deleteAllLocalData()`, `PrivacyFilter` redacts tokens/coordinates in backend logs, no analytics/tracking
- **Theme**: Always dark mode, cybersecurity aesthetic (navy/violet/magenta), premium components (GlassCard, GlowRing, SosButton, etc.)
- **Architecture**: Clean Architecture + Riverpod 2.x + go_router, platform interfaces composed in `core/providers.dart`

### Changed
- Removed app lock/PIN/biometric authentication (by design — immediate emergency access)
- Removed Firebase, Google Mobile Services from core features
- Location engine: GMS-free `LocationManager` (GPS + NETWORK) for F-Droid compatibility

### Known Limitations
- Shake SOS cold launch behind lock screen requires `SYSTEM_ALERT_WINDOW` (Android 14+)
- LiveSharingService uses `com.google.android.gms.location` (GMS dependency — F-Droid blocker)
- Check-in reminders use inexact alarms (may drift)
- Force-stop cancels alarms (healed on next app open)
- No guaranteed delivery of any emergency communication

---

## [Unreleased]

### Planned
- F-Droid compatibility resolution for LiveSharingService
- Release signing configuration
- Additional OEM battery guidance
- Accessibility improvements