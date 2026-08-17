# AGENTS.md

Flutter application (Dart SDK `^3.13.0`, Flutter >= 3.18). This is currently a stock `flutter create` template — no state management, routing, or backend yet.

## Commands

- `flutter pub get` — resolve dependencies (run after editing `pubspec.yaml`)
- `flutter analyze` — static analysis (uses `flutter_lints` via `analysis_options.yaml`)
- `flutter test` — run the widget test suite
- `flutter run` — launch the app (hot reload = `r`, hot restart = `R`)

## Structure

- `lib/` — all Dart application code; entrypoint is `lib/main.dart`
- `test/` — widget tests
- `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` — generated platform scaffolding; excluded from analysis and should not be hand-edited for app logic

## Gotchas

- Analyzer excludes all `build/` and platform directories; only `lib/` and `test/` are linted.
- Dart 3 shorthand syntax is used in template code (e.g. `colorScheme: .fromSeed(...)`), so dot-shorthands compile fine on this SDK.