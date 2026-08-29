# Contributing to GuardianHer

Thank you for contributing to GuardianHer — a safety-critical application where reliability and honesty matter more than features.

## Code of Conduct

- **Safety first**: Never weaken SOS reliability, location integrity, privacy, or fail-closed behavior
- **Honest communication**: Never claim "sent" or "delivered" — only "opened" or "attempted"
- **No silent failures**: Errors must surface to the user
- **Minimal permissions**: Don't add permissions without clear safety justification
- **Respect user agency**: All features opt-in, user-initiated, visible

---

## Getting Started

### Prerequisites
- Flutter SDK ^3.13.0 (Flutter 3.18+)
- Android SDK: platforms 34, 35, 36; build-tools 36.0.0; NDK 28.2.13676358; CMake 3.22.1
- JDK 17
- Git

### Setup
```bash
git clone <repository-url>
cd guardianher
flutter pub get
flutter analyze
flutter test
```

### Run Debug
```bash
flutter run
```

### Run Backend (Optional)
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8080
```

---

## Development Workflow

1. **Create an issue** — Discuss the change before implementing (especially for safety features)
2. **Branch** — `git checkout -b feature/description` or `fix/description`
3. **Implement** — Follow existing patterns (Clean Architecture, Riverpod, platform interfaces)
4. **Test** — Add/update tests; all tests must pass
5. **Analyze** — `flutter analyze` must pass with zero issues
6. **Commit** — Clear, conventional commit messages
7. **PR** — Reference the issue; describe testing performed

---

## Architecture Conventions

### Clean Architecture Layers (per feature)
```
features/<name>/
  domain/         # Entities, repositories (interfaces), failures, pure logic
  application/    # Controllers, providers, state, use cases
  data/           # Repository implementations, datasources, platform channels
  presentation/   # Screens, widgets, UI logic
```

### Platform Interfaces
- All platform functionality behind interfaces in `lib/core/platform/`
- Implementations in `lib/data/`
- Wired in `lib/core/providers.dart`
- Tests override with fakes from `test/helpers/fakes.dart`

### State Management
- Riverpod 2.x (`flutter_riverpod`)
- Controllers = `Notifier`/`AsyncNotifier` providers
- State = immutable classes (freezed-style or manual)
- No `setState` in feature code

### Navigation
- `go_router` with `ShellRoute` for bottom nav (Home, Journey, Contacts, Activity, Settings)
- Full-screen routes: SOS, Location, Live Location, Check-In, Permissions, Settings sub-pages
- Route guards in `lib/core/routing/route_guards.dart`

### Testing
- Widget tests in `test/features/<name>/`
- Unit tests for pure logic
- Shared fakes in `test/helpers/fakes.dart` and `test/features/sos/sos_test_fakes.dart`
- **Critical**: Tests ending mid-SOS/Journey/Live-Location must call `cancelSos`/`endJourney`/`stopSession` or pending timers fail the run
- Use `fake_async` for timer-dependent tests
- Backend tests: `cd backend && python -m pytest tests -q`

---

## Safety-Critical Rules

### NEVER
- Add `ACCESS_BACKGROUND_LOCATION`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `SCHEDULE_EXACT_ALARM`
- Claim delivery/sending — only "composer opened" / "attempted"
- Log coordinates, phone numbers, tokens, message bodies, vehicle registrations
- Add analytics/tracking
- Weaken SOS priority (SOS always interrupts Journey/Check-In)
- Remove fail-closed behavior (errors must surface)

### ALWAYS
- Use `flutter_secure_storage` for sensitive data (contacts, tokens, history)
- Use `shared_preferences` only for non-sensitive prefs (theme, locale, onboarding)
- Keep platform channels guarded by feature controllers (other platforms never touch)
- Override platform providers in tests via `defaultOverrides`
- Document Android/OEM limitations honestly

---

## Platform-Specific Notes

### Android
- `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`
- Kotlin services in `android/app/src/main/kotlin/com/guardianher/app/`
- Manifest declares receivers/services with `exported` attributes per Android 12+
- `permission_handler` pinned to `^12.0.0` (API 37 not available in toolchain)
- `flutter_secure_storage` forced to `compileSdk = 36` via `afterEvaluate` hook

### iOS
- Platform scaffolding only; no iOS-specific safety features implemented

### Backend (Optional)
- FastAPI + SQLAlchemy + SQLite (dev) / PostgreSQL (prod)
- Configuration via environment variables only
- Tokens: SHA-256 hash stored; public endpoints return identical `{"status":"ended"}` for unknown/expired
- Rate limits: in-memory fixed windows (per-instance)

---

## Pull Request Checklist

- [ ] `flutter analyze` passes (zero issues)
- [ ] `flutter test` passes (all 482+ widget/unit tests)
- [ ] Backend tests pass (`cd backend && python -m pytest tests -q` — 34+ tests)
- [ ] No new permissions added without justification
- [ ] No secrets/credentials in code or commits
- [ ] Documentation updated (README, CHANGELOG, code comments if needed)
- [ ] Safety-critical paths tested manually on device (emulator insufficient for Shake SOS, background services)
- [ ] Commit messages follow conventional format

---

## Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `security`

Scopes: `sos`, `shake`, `checkin`, `journey`, `live`, `location`, `contacts`, `recorder`, `core`, `android`, `backend`, `ui`

Example:
```
feat(sos): add auto-retry on location timeout

- Schedule one retry (15s) when capture ends with timeout status
- Guard retry on SOS still active; cancel on stop
- Update SOS location section to show timeout state

Closes #123
```

---

## Release Process

1. Version bump in `pubspec.yaml` (semver)
2. Update `CHANGELOG.md`
3. `flutter analyze` + `flutter test` + backend tests
4. `flutter build apk --release` (configure release keystore first)
5. Tag: `git tag v<version>`
6. Push: `git push origin main --tags`

---

## Questions?

Open an issue for discussion. For security vulnerabilities, see [SECURITY.md](SECURITY.md).