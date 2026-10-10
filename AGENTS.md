# AGENTS.md

Aves — a Flutter/Android gallery and metadata explorer app. This is an application, not a library, and it is a **fork** of `deckerst/aves` (upstream does not accept PRs, see `README.md`). The root is the app and `plugins/*` are members of a single pub workspace.

Read the critical rules first, then the toolchain and workflow sections.

## Critical rules

- Never push to `upstream`. Never commit on `main`. Do development on `muzei-dev`.
- New features go in `lib/features/<feature>/`, not scattered into upstream-owned trees.
- Never hardcode user-facing strings: every new string ships its `app_en.arb` key (other locales are translated later).
- Never change a database schema version without a matching migration and test.
- Run code generation after any Drift/Freezed change; generated files are committed.
- Never commit a flavor swap or generated `lib/l10ngen/`.
- Do not refactor, rename, or reformat upstream/adapted code beyond what the task needs.
- No placeholders or `TODO`s: `./flutterw analyze` and `./flutterw test` must pass.

## Remotes & push policy

- `upstream` = `deckerst/aves` (**public, third-party**). It is used **only to pull/fetch code**. **Never push to it** — its push URL is intentionally set to `DISABLE`, so a push attempt fails.
- `origin` = `tifiyitifi/aves-muzei-st-private` (**private**). All work is pushed here.
- Keep `main` an unmodified mirror of `upstream/main`; do development on the `muzei-dev` branch instead of committing on `main`.

## Fork discipline & feature layout

This repo is a fork, so keeping the diff against `upstream` small matters more than any local style preference — it decides whether upstream updates stay mergeable.

- Put every **new feature** in `lib/features/<feature>/` as a self-contained slice (`model/`, `services/`, `widgets/`, plus `view/`, `provider/`, `db/` as needed).
- Touch upstream-owned trees (`lib/model`, `lib/services`, `lib/widgets`, `lib/view`, `lib/convert`, ...) only for the minimum cross-cutting wiring (DI/`get_it` registration, a route, a settings entry point).
- Keep changes additive and localized so a fork slice can be dropped cleanly if upstream ships the same capability.

## Toolchain and setup

- Flutter is pinned via the `.flutter` git submodule and invoked through `./flutterw` (passsy/flutter_wrapper). The pinned version lives in `pubspec.yaml` (`flutter:` under `environment`) and `.metadata`.
- `.flutter` is uninitialized on a fresh clone; `./flutterw` auto-runs `git submodule update --init` (needs network). Running a system-wide `flutter` directly uses the wrong pinned version.
- `./flutterw` and every `scripts/*.sh` are POSIX shell scripts; there is no `.bat`/`.ps1` wrapper, so run them from a bash-like shell on Windows.
- `android/settings.gradle.kts` requires `android/local.properties` containing `flutter.sdk` (created by Flutter tooling).
- Signed builds need `android/key.properties` copied from `android/key_template.properties` (also holds `googleApiKey`). Without it, release signing is skipped.
- Debug/profile builds are signed with the shared keystore committed at `android/app/debug.keystore` (alias `androiddebugkey`, password `android`), so builds from different machines share one signature and can update each other.
- The Android `versionCode` is kept in `android/version.properties` and auto-incremented by `.githooks/pre-commit`; enable the hook once per clone with `git config core.hooksPath .githooks` (the build falls back to the pubspec build number if the file is missing).
- JDK 21 is required; Gradle downloads Temurin via the foojay toolchain resolver if absent.

## Flavors (read this before any build/run)

There are four flavors: `play`, `izzy`, `libre`, `custom` (the last is the private fork build with a distinct application id and no Crashlytics). Flavor dependencies are set by swapping the root manifest, not by conditionals:

- `scripts/apply_flavor_<flavor>.sh` copies `flavors/pubspec_<flavor>.yaml` and `.lock` over the root `pubspec.yaml`/`pubspec.lock`, then runs `pub get --enforce-lockfile`.
- Always apply the matching flavor before `pub get`/`run`/`build`. Entrypoints: `lib/main_play.dart`, `lib/main_izzy.dart`, `lib/main_libre.dart`, `lib/main_custom.dart` (plus `lib/main_play_test_editor.dart` for intent debugging).
- Applying a flavor overwrites tracked root files, so `git diff` will show them; don't commit flavor swaps by accident.
- Platform backends are swapped by choosing different workspace members that share the same Dart package name:
  - `aves_services_google` (play, izzy, custom) vs `aves_services_none` (libre) → imported as `aves_services_platform`.
  - `aves_report_crashlytics` (play) vs `aves_report_console` (izzy, libre, custom) → imported as `aves_report_platform`.
  - Video uses `aves_video_mpv`; `aves_video_exo` exists but is commented out in every flavor.
- The committed root `pubspec.yaml` is the `play` variant; `pubspec.lock` may not match `flavors/pubspec_play.lock`.
- Every pub dependency lives in **all** `flavors/pubspec_<flavor>.yaml` (+ `.lock`), since a flavor swap replaces the root manifest. Add new dependencies there too, or regenerate the flavor files.

## Commands

Order matters: `pub get` → codegen (if needed) → `gen-l10n` → `analyze`/`test`/build.

- `./flutterw pub get` — a single root command resolves all workspace packages.
- Code generation (required after any Drift/Freezed change; run with the pinned SDK): `./flutterw pub run build_runner build --delete-conflicting-outputs`.
- `./flutterw gen-l10n` — **required**. `lib/l10ngen/` is generated and gitignored, and is imported by `lib/l10n/l10n.dart` and `lib/theme/styles.dart`; nothing compiles until it exists. Re-run after editing any `.arb`.
- `./flutterw analyze`
- `./flutterw test`
- Single test file: `./flutterw test test/model/filters_test.dart`
- Single test name: `./flutterw test --plain-name "some test"`
- Run: `./flutterw run -t lib/main_play.dart --flavor play`
- Profile build (what CI uses to type-check Android): `./flutterw build apk --profile -t lib/main_play.dart --flavor play`
- Screenshots: `./flutterw drive --flavor play -t test_driver/driver_screenshots.dart --profile` (needs a connected device/emulator), then `scripts/screenshot_post_process.sh` (needs ImageMagick 6).

CI (`quality-check.yml`) runs exactly: `pub get`, `gen-l10n`, `analyze`, `test`. Generated code is committed, so CI does not run codegen.

CI (`build-custom-apk.yml`) builds a signed `custom`-flavor release APK on pushes/PRs to `muzei-dev`/`main`/`release` (and manual dispatch) and uploads it as an artifact. Signing secrets: `KEYSTORE`, `STORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS` (optional `GOOGLE_API_KEY`). A push to the **`release`** branch additionally auto-tags `v<X.Y.Z>` (skipped when the tag already exists), extracts that section from `CHANGELOG.md` via `scripts/extract_log.py`, and publishes a GitHub Release with the APK and `SHA256SUMS.txt`. So a release is created only when `X.Y.Z` is bumped.

## Architecture & layering

- `lib/model` (domain), `lib/view/src` + `lib/view/view.dart` (shared enums/actions re-exported across layers), `lib/services` (platform-facing, registered via `get_it`), `lib/widgets` (UI).
- `lib/features/**` is the fork-only layer for new features, isolated from upstream-owned trees.
- Many files are deliberate adaptations of Flutter/package sources (`lib/widgets/common/basic/*`, `lib/services/common/output_buffer.dart`, etc.; the full list is in `pubspec.yaml` comments). Keep them close to upstream rather than refactoring them as ordinary app code.

## Tech stack for new features (`lib/features/**`)

New fork-only features must reuse the existing stack, not introduce a parallel one.

- **State:** keep `provider` + `ChangeNotifier`. Expose feature state as a `ChangeNotifier` (or an immutable value held by one) and read shared state via `context.select`/`context.watch` (`Settings`, `CollectionSource`, `CollectionLens`, ...). **Do not add a second global-state library.**
- **Widgets:** `HookWidget` (`flutter_hooks`) is allowed for feature-local ephemeral state and controllers; keep `StatefulWidget` where a custom `State` lifecycle is needed. Do not retrofit existing/upstream widgets to hooks.
- **Services:** register platform-facing services with `get_it`, as the rest of the app does.
- **Models:** for **new feature** value/DTO/state models use `freezed` (+ `json_serializable` when serialized); codegen is already in the toolchain, and it removes hand-written `copyWith`/`==`/`hashCode`. Keep **entities / mutable identity-based models** (e.g. `AvesEntry`) and upstream models (`lib/model`, `aves_model`) hand-written + `equatable`; do not convert them. Use plain Dart `enum`s, and map Drift row classes to feature models via adapters (never expose Drift types to the UI).
- **Dependencies:** prefer reusing existing packages; every new dependency must also land in the flavor manifests (see Flavors).

## Persistence & database

- Persist through the app's single database layer; do not open ad-hoc SQLite connections or side files. Keep the existing `LocalMediaDb` / `SettingsStore` interfaces as the seam so the backing engine stays swappable.
- **Migrations:** never change the schema version without a matching migration and a test that upgrades from the previous version. Migrations are forward-only and verified.
- **Settings persistence migration** (SharedPreferences → database) must stay **rollback-safe**: a gate selects the authoritative source, and disabling it restores the previous behaviour losslessly. Unavailable settings rows are hidden, not merely inert.
- **Threading:** heavy database work must not run on the UI isolate.
- **Generated code:** codegen output (`*.g.dart`, `*.freezed.dart`) is committed and confined to fork-owned paths; regenerate after schema/model changes.
- Data-migrating changes need a backup/verify/rollback story before release.

## Localization

- ARB sources: `lib/l10n/app_<lang>.arb`, template `app_en.arb`; config in `l10n.yaml`. Generated output goes to `lib/l10ngen/`.
- Development is **English-only**: add every new UI string to `app_en.arb` in the same change. Other locales (`app_zh.arb`, ...) are translated **afterwards**, written directly into their ARB files.
- Never hardcode user-facing strings or build display text by concatenation; consume via `context.l10n.<key>` and use ARB placeholders with runtime args.
- When adding a platform locale also update `android/app/src/main/res/values-<lang>/strings.xml` and `lib/widgets/settings/language/locales.dart`.

## Testing

- Unit/widget tests live in `test/` (run with `./flutterw test`); integration driver tests live in `test_driver/` and run via `./flutterw drive` on a connected device/emulator (they are not picked up by `flutter test`).
- **TDD for behaviour changes** in testable layers (`lib/model`, `lib/services` logic, `lib/utils`, filters/parsers, and `lib/features/*/model|services`): Red → Green → Refactor — write or adjust the failing test first.
- **Exempt:** UI widgets/layout, adapted third-party sources, platform channels (video/Google/report/Android native), and flavor/build config. For bug fixes, add a regression test that reproduces the bug first whenever feasible.
- Tests that need platform services must call `setUpAllServices()` / `setUpServices()` from `test/common.dart`, which registers in-memory fakes (SharedPreferences, media/db/storage services). Don't hit real platform channels.
- Database tests use an in-memory database; `test/common.dart` forces a POSIX `p.Context` so path tests behave the same on Windows.

## Version bump checklist

From the comment in `pubspec.yaml`, in order: bump `version:` in `pubspec.yaml`, update `CHANGELOG.md`, update `whatsnew/whatsnew-en-US`, then run `scripts/apply_version_bump.sh` (regenerates changelogs + all three flavor manifests).

- The `+N` build number is derived from `android/version.properties` and is rewritten by `scripts/sync-version-code.sh` (called by `.githooks/pre-commit`, covering the root pubspec **and** every `flavors/pubspec_*.yaml`). **Never hand-edit `+N`** — only the `X.Y.Z` marketing version is manual.
- Release tags are `v<X.Y.Z>` (the `+N` part is dropped).

## AI session conventions

- Reply in the user's language (Chinese / English / mixed).
- Keep the working tree **uncommitted** during a session so `git status` / `git diff` show exactly what the AI changed.
- Commit only on an explicit user request, on the working branch (never `main`), with an English conventional-commit message. Never push to `upstream`.
- Never commit a flavor swap (`scripts/apply_flavor_*` output) or generated `lib/l10ngen/`.
- Because `.githooks/pre-commit` auto-bumps `android/version.properties`, exclude that file from AI-authored commits.
- No placeholders, partial code, or `// TODO: implement later`; every change must compile and pass `./flutterw analyze` + `./flutterw test`.
- Comments explain the "Why"/design intent, not the "What"; concise English.

## Code conventions

- `analysis_options.yaml`: `formatter.page_width: 240`, `trailing_commas: preserve`; enforced lints include single quotes, `always_declare_return_types`, `unawaited_futures`, and `prefer_const_*`.
- Prefer `const` constructors, avoid `dynamic`, and declare explicit return types.
