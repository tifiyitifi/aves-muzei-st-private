# Grouped wallpaper — testing

A behaviour change is not finished until the gates agree. They answer different
questions and none replaces another.

| Gate | Question | Cost |
| --- | --- | --- |
| `analyze` | does the code type-check under the repo's lints | seconds |
| `test` | does every named Dart rule still hold | minutes |
| Kotlin unit tests | do the native decisions still hold | minutes |
| Rule register check | does every `F:` token still resolve | seconds |
| Device checklist | does it work where the wallpaper really is | one run |
| Privacy gate | does the change leak a local path | seconds |

## 1. Analysis

```sh
./flutterw analyze
```

On Windows the wrapper is `./flutterw` from a bash-like shell; the pinned SDK can
also be called directly as `.flutter/bin/flutter.bat analyze`.

## 2. Host tests

```sh
./flutterw test test/features/grouped_wallpaper
```

Which file holds which rule family:

| File | Rule families |
| --- | --- |
| `test/features/grouped_wallpaper/grouped_wallpaper_engine_test.dart` | `DISP-1` … `DISP-7`, `PROM-1`, `SIZE-1`, `SIZE-2` |
| `test/features/grouped_wallpaper/grouped_wallpaper_restore_notice_test.dart` | `RSTR-1`, `RSTR-2` |
| `test/features/grouped_wallpaper/wallpaper_capability_test.dart` or `model/wallpaper_capability_test.dart` | supporting cases for `SIZE-2` |
| `test/features/grouped_wallpaper/grouped_wallpaper_engine_test.dart` (`displayed slot` group) | the display rules |
| `test/features/grouped_wallpaper/grouped_wallpaper_state_test.dart` | the pure display selection, if it is moved there |
| `test/features/grouped_wallpaper/grouped_wallpaper_view_actions_test.dart` | `NAV-2` (push versus pop) |

Database tests need a full native sqlite3 on a Windows host; see `AGENTS.md`
(`AVES_SQLITE3_DLL`). The Microsoft `winsqlite3.dll` is not a substitute.

## 3. Kotlin unit tests

```sh
cd android
./gradlew :app:testCustomDebugUnitTest "-Ptarget=lib/main_custom.dart"
```

The native decision tables that the Dart side cannot reach live here:

| Class | Rules |
| --- | --- |
| `GroupedDisplayTest` | `RET-1`, `RET-3` |
| `GroupedTextureRetentionTest` | `RET-2` |
| `GroupedAdvanceRequestQueueTest` | `PROM-2` |
| `GroupedTapGateTest` | `PROM-3` |
| `GroupedWallpaperFileStateTest` | the state file contract |

JDK 21 is required. The `-Ptarget` property matters: without it Gradle looks for
`lib/main.dart`, which this app does not have.

## 4. Rule register check

```sh
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-grouped-wallpaper-rules.ps1
```

It parses `rules.md`, resolves every `F:` token against `test/**` (a `test('name'`
or `testWidgets('name'` declaration both count), and checks that every
`decisions/` link exists. Exit code 1 means a row claims coverage it does not
have, or a link points nowhere. It is not part of `flutter test` because a doc
edit should not need the test runner.

A row with only `-:<reason>`, `-:native <class>` or `M` is allowed; it is
unfalsified, and the reason says why. Prefer adding the fixture to widening the
reason.

**Order matters.** A new rule may be written with its `F:` token before the test
exists; the checker is red until the test is written in the same change. That is
the TDD order, not a broken gate.

## 5. Device checklist

No host fixture can prove these; `rules.md` marks them `M` or `native`.

- **R7 / `SWITCH-1`** — leave any app to the home screen and watch the
  transition. Record whether the previous Muzei wallpaper appears first, and
  whether the log shows `engine.destroy` / `engine.create` around each return.
- **R7b / `SWITCH-1`** — after a package replace (`PACKAGE_UPDATE_FINISHED` in
  `dumpsys wallpaper`), swipe home: the launcher's cached frame comes back.
  Set the current group as wallpaper once (`SET_LIVE`), change the photo, and
  swipe home again; it must show the live photo.
- **R5** — update the app, or force-stop it, then confirm the in-app restore
  strip and the one-tap notification (on an OEM that resets the wallpaper).
- **R3** — tap the wallpaper quickly twice while the next slot is still baking;
  both steps must land.
- **R2** — return to the home screen after the wallpaper was hidden; it must show
  the photo, never the grey placeholder.
- **`NAV-1` / `NAV-2`** — double-tap the wallpaper to open the view, then press
  back: it must land on the launcher's home screen (with the configured warning
  when "back twice to exit" is on). From the view, 「Open wallpaper groups」 must
  push the playing group's page; back must return to the view, and the view's
  back must then leave to the desktop. Open the view from the group page's menu:
  back must return to the group page.

## 6. Gates before a commit

```sh
./flutterw analyze
./flutterw test test/features/grouped_wallpaper
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-grouped-wallpaper-rules.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-local-paths.ps1
```

The Kotlin unit task and the device checklist run when the change touches the
native renderer or a rule marked `M`.
