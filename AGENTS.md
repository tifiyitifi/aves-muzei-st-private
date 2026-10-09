# AGENTS.md

Aves — a Flutter/Android gallery and metadata explorer app. This is an application, not a library; upstream does not accept PRs (see `README.md`). The root is the app and `plugins/*` are members of a single pub workspace.

## Remotes & push policy

- `upstream` = `deckerst/aves` (**public, third-party**). It is used **only to pull/fetch code**. **Never push to it** — its push URL is intentionally set to `DISABLE`, so a push attempt fails.
- `origin` = `tifiyitifi/aves-muzei-st-private` (**private**). All work is pushed here.
- Keep `main` an unmodified mirror of `upstream/main`; do development on the `muzei-dev` branch instead of committing on `main`.

## Toolchain and setup

- Flutter is pinned via the `.flutter` git submodule and invoked through `./flutterw` (passsy/flutter_wrapper). The pinned version lives in `pubspec.yaml` (`flutter:` under `environment`) and `.metadata`.
- `.flutter` is uninitialized on a fresh clone; `./flutterw` auto-runs `git submodule update --init` (needs network). Running a system-wide `flutter` directly uses the wrong pinned version.
- `./flutterw` and every `scripts/*.sh` are POSIX shell scripts; there is no `.bat`/`.ps1` wrapper, so run them from a bash-like shell on Windows.
- `android/settings.gradle.kts` requires `android/local.properties` containing `flutter.sdk` (created by Flutter tooling).
- Signed builds need `android/key.properties` copied from `android/key_template.properties` (also holds `googleApiKey`). Without it, release signing is skipped.
- JDK 21 is required; Gradle downloads Temurin via the foojay toolchain resolver if absent.

## Flavors (read this before any build/run)

There are three flavors: `play`, `izzy`, `libre`. Flavor dependencies are set by swapping the root manifest, not by conditionals:

- `scripts/apply_flavor_<flavor>.sh` copies `flavors/pubspec_<flavor>.yaml` and `.lock` over the root `pubspec.yaml`/`pubspec.lock`, then runs `pub get --enforce-lockfile`.
- Always apply the matching flavor before `pub get`/`run`/`build`. Entrypoints: `lib/main_play.dart`, `lib/main_izzy.dart`, `lib/main_libre.dart` (plus `lib/main_play_test_editor.dart` for intent debugging).
- Applying a flavor overwrites tracked root files, so `git diff` will show them; don't commit flavor swaps by accident.
- Platform backends are swapped by choosing different workspace members that share the same Dart package name:
  - `aves_services_google` (play, izzy) vs `aves_services_none` (libre) → imported as `aves_services_platform`.
  - `aves_report_crashlytics` (play) vs `aves_report_console` (izzy, libre) → imported as `aves_report_platform`.
  - Video uses `aves_video_mpv`; `aves_video_exo` exists but is commented out in every flavor.
- The committed root `pubspec.yaml` is the `play` variant; `pubspec.lock` may not match `flavors/pubspec_play.lock`.

## Commands

Order matters: `pub get` → `gen-l10n` → `analyze`/`test`/build.

- `./flutterw pub get` — a single root command resolves all workspace packages.
- `./flutterw gen-l10n` — **required**. `lib/l10ngen/` is generated and gitignored, and is imported by `lib/l10n/l10n.dart` and `lib/theme/styles.dart`; nothing compiles until it exists. Re-run after editing any `.arb`.
- `./flutterw analyze`
- `./flutterw test`
- Single test file: `./flutterw test test/model/filters_test.dart`
- Single test name: `./flutterw test --plain-name "some test"`
- Run: `./flutterw run -t lib/main_play.dart --flavor play`
- Profile build (what CI uses to type-check Android): `./flutterw build apk --profile -t lib/main_play.dart --flavor play`
- Screenshots: `./flutterw drive --flavor play -t test_driver/driver_screenshots.dart --profile` (needs a connected device/emulator), then `scripts/screenshot_post_process.sh` (needs ImageMagick 6).

CI (`quality-check.yml`) runs exactly: `pub get`, `gen-l10n`, `analyze`, `test`.

## Version bump checklist

From the comment in `pubspec.yaml`, in order: bump `version:` in `pubspec.yaml`, update `CHANGELOG.md`, update `whatsnew/whatsnew-en-US`, then run `scripts/apply_version_bump.sh` (regenerates changelogs + all three flavor manifests).

## Localization

- ARB sources: `lib/l10n/app_<lang>.arb`, template `app_en.arb`; config in `l10n.yaml`. Generated output goes to `lib/l10ngen/`.
- When adding a locale also update `android/app/src/main/res/values-<lang>/strings.xml` and `lib/widgets/settings/language/locales.dart`.

## Testing

- Unit/widget tests live in `test/` (run with `./flutterw test`); integration driver tests live in `test_driver/` and run via `./flutterw drive` on a connected device/emulator (they are not picked up by `flutter test`).
- Tests that need platform services must call `setUpAllServices()` / `setUpServices()` from `test/common.dart`, which registers in-memory fakes (SharedPreferences, media/db/storage services). Don't hit real platform channels.
- `test/common.dart` forces a POSIX `p.Context` so path tests behave the same on Windows.

## Code conventions

- `analysis_options.yaml`: `formatter.page_width: 240`, `trailing_commas: preserve`; enforced lints include single quotes, `always_declare_return_types`, `unawaited_futures`, and `prefer_const_*`.
- Many files are deliberate adaptations of Flutter/package sources (`lib/widgets/common/basic/*`, `lib/services/common/output_buffer.dart`, etc.; the full list is in `pubspec.yaml` comments). Keep them close to upstream rather than refactoring as ordinary app code.
- Main layering: `lib/model` (domain), `lib/view/src` + `lib/view/view.dart` (shared enums/actions re-exported across layers), `lib/services` (platform-facing, registered via `get_it`), `lib/widgets` (UI).
