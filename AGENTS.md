# Repository Guidelines

## Project Structure & Module Organization
This repository contains a Flutter client and a small Go backend.

- `lib/`: Flutter app code (`pages/`, `services/`, `providers/`, `widgets/`, `models/`).
- `test/`: Dart/Flutter tests, including widget and service tests (`*_test.dart`).
- `assets/`: app assets and site definitions (`assets/sites/` + generated `assets/sites_manifest.json`).
- `server/`: Go API service (`main.go`, `cmd/`, `migrations/`, `admin/`).
- Platform folders: `android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`.

## Build, Test, and Development Commands
- `flutter pub get`: install Flutter dependencies.
- `flutter run`: run app in debug mode.
- `flutter build apk --release`: build Android release APK.
- `flutter analyze`: run static analysis with configured lints.
- `flutter test`: run all Flutter tests.
- `./generate_sites_manifest.sh`: regenerate site manifest after editing `assets/sites/*`.
- `cd server && go run .`: run backend locally.
- `cd server && go test ./...`: run backend tests.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`flutter_lints`); keep analyzer warnings at zero.
- Use Dart formatting defaults (`dart format .`): 2-space indentation, trailing commas where helpful.
- File names: `snake_case.dart`; classes/enums: `PascalCase`; methods/variables: `camelCase`.
- Keep feature code grouped by domain (for example, adapter logic under `lib/services/api/`).

## Testing Guidelines
- Flutter tests use `flutter_test`; backend uses Go’s built-in `testing` package.
- Name tests with `*_test.dart` and `*_test.go`.
- Add or update tests for behavior changes in adapters, parsing, storage, and widgets.
- Run both app and server tests before opening a PR when touching both modules.
- No fixed coverage gate is enforced; prioritize meaningful assertions for changed paths.

## Commit & Pull Request Guidelines
- Use Conventional Commit-style prefixes seen in history: `feat:`, `fix:`, `refactor:`, `chore:`, `release:`.
- Keep commits focused and descriptive (example: `feat: add Unit3D category mapping`).
- PRs should include:
  - clear summary of behavior changes,
  - linked issue/PR number when applicable (for example `#93`),
  - screenshots/GIFs for UI changes,
  - notes for config/data updates (especially `assets/sites/` and manifest regeneration).

## Release Guidelines
- **Publishing a GitHub Release must also update the repository homepage `README.md`** in the same change: the version line (`当前版本 **ohos-vX.Y.Z**（应用版本 \`A.B.C+N\`）`), the 「在自用版中新增的功能」 section, and the 「已修复的问题」 section. Commit and push README and code *before* creating the Release and uploading assets, so the homepage never shows a stale version.
- Keep `pubspec.yaml` `version:` and `ohos/local.properties` `flutter.versionCode` in sync with the published build.
- HarmonyOS releases follow the `ohos-vX.Y.Z` tag scheme and keep `versionName` unchanged while incrementing the build number (e.g. `2.29.5+216` → `2.29.5+217`).
- Attach the unsigned HAP (`hap/PTMate-<build>-unsigned.hap`) plus its `.sha256` to the Release.
- iOS IPAs are **not** uploaded to GitHub: they stay in the local `IPA/` folder and the Codemagic artifact store only.
- After building a HAP, place it in `hap/PTMate-<build>-unsigned.hap` with a matching `.sha256`, and archive superseded builds with `./scripts/archive_hap.sh` (or use `./scripts/build_hap.sh`, which does build + checksum + archive in one step). The `hap/` top level keeps only the current build; older ones live in `hap/archive/`.
