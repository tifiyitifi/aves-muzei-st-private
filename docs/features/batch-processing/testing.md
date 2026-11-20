# Batch processing — testing

A behaviour change is not finished until the gates agree. They answer different
questions and none replaces another.

| Gate | Question | Cost |
| --- | --- | --- |
| `analyze` | does the code type-check under the repo's lints | seconds |
| `test` | does every named rule still hold | minutes |
| `compileCustomDebugKotlin` | does the Android side still build | minutes |
| Rule register check | does every `F:` token still resolve | seconds |
| Device checklist | does it work where the files really are | one run |
| Privacy gate | does the change leak a local path | seconds |

## 1. Analysis

```sh
./flutterw analyze
```

On Windows the wrapper is `./flutterw` from a bash-like shell; the pinned SDK can
also be called directly as `.flutter/bin/flutter.bat analyze`.

## 2. Host tests

```sh
./flutterw test
```

The batch feature and its schema migration:

```sh
./flutterw test test/features/batch_ops
./flutterw test test/features/drift_db/migration_v17_test.dart
```

Which file holds which rule family:

| File | Rule families |
| --- | --- |
| `test/features/batch_ops/batch_action_test.dart` | `RUN-1`, `RUN-3`, `RUN-7`, `RUN-8`, `PRF-6`, `PRF-7` |
| `test/features/batch_ops/batch_paths_test.dart` | `CLS-1` … `CLS-4`, `SHR-1` … `SHR-5` |
| `test/features/batch_ops/batch_run_controller_test.dart` | `RUN-2`, `REC-1`, `REC-2` |
| `test/features/batch_ops/batch_result_store_test.dart` | `REC-7` … `REC-9`, `REP-4`, `PRF-1` … `PRF-4`, `SHR-17` |
| `test/features/batch_ops/batch_results_service_test.dart` | `REC-3` … `REC-5`, `REP-1`, `REP-3`, `APP-1`, `APP-2`, `APP-4`, `APP-5`, `HOU-1`, `SHR-6` |
| `test/features/batch_ops/batch_settings_test.dart` | `SHR-15`, `SHR-16`, `SHR-18` |
| `test/features/batch_ops/batch_share_service_test.dart` | `SHR-9` … `SHR-14` |
| `test/features/drift_db/migration_v17_test.dart` | `SCH-1`, `SCH-2` |
| `test/utils/android_file_utils_test.dart` | `SHR-7` |

Database tests need a full native sqlite3 on a Windows host; see `AGENTS.md`
(`AVES_SQLITE3_DLL`). The Microsoft `winsqlite3.dll` is not a substitute.

## 3. Android build

```sh
cd android
./gradlew :app:compileCustomDebugKotlin "-Ptarget=lib/main_custom.dart"
```

JDK 21 is required. The target property matters: without it Gradle looks for
`lib/main.dart`, which this app does not have.

## 4. Rule register check

```sh
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-batch-rules.ps1
```

It parses `rules.md`, resolves every `F:` token against `test/**`, and
checks that every `decisions/` link exists. Exit code 1 means a row claims
coverage it does not have, or a link points nowhere. It is not part of `flutter
test` because a doc edit should not need the test runner.

A row with only `-:<reason>` or `M` is allowed; it is unfalsified, and the reason
says why. Prefer adding the fixture to widening the reason.

## 5. Device checklist

Run these on a device with real storage. Describe what you did by kind, never by
file name.

1. Select a few photos in the collection, choose Batch process, enable a filter
   and a resize, run. Expect per-item progress and a snackbar offering VIEW.
   (`RUN-1`, `RUN-3`)
2. Open the results album. It is grouped under Apps, and the banner shows the
   pending count. (`CLS-1`, `CLS-6`)
3. Replace one result. Expect one write-access prompt for the selection, then
   the original updated and the row gone. (`APP-1`, `APP-4`)
4. Run again on the same photo in replace-previous mode. Expect one result with
   the plain name, no ` (1)` copy. (`REP-1`)
5. Switch to keep versions and run twice. Expect two dated results. (`REP-3`)
6. Move one result back. Expect it in the source album; a same-named file is
   renamed, not overwritten. (`APP-5`)
7. Delete a result from the album, then reopen the results page. Expect the row
   gone. (`HOU-1`)
8. Cancel a run after a few items. Expect the finished results kept and the rest
   reported as cancelled. (`RUN-4`)
9. Force one item to fail (for example a corrupt source) and run a selection
   with good items around it. Expect the good ones to finish. (`RUN-5`)
10. Select photos and choose Copy & share. On the first run the explainer names
    the temporary folder and offers Settings; Continue opens the sheet. (`SHR-20`)
11. Run it. Expect the copies in the share album under Apps, the batch results
    table empty, and a snackbar whose VIEW opens the share album. (`SHR-6`,
    `SHR-7`, `SHR-19`)
12. Save a share profile in the share sheet. It is not listed in the batch
    settings page, and a batch profile is not listed in the share page.
    (`SHR-17`)
13. Set retention to one day. A copy older than a day is removed when the share
    settings page opens or the next share run starts; a fresh copy and a batch
    result stay. (`SHR-9` … `SHR-13`)
14. Dismiss the explainer, then start copy & share again (also after resetting
    the preferences): it does not return. (`SHR-18`)
15. Cancel a share run after a few items. Expect the finished copies kept.
    (`RUN-4`)

## 6. Privacy gate

```sh
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-local-paths.ps1 -All
```

Run it after editing docs, and before any commit that touches them. It is also
wired into `.githooks/pre-commit`, `commit-msg` and `pre-push`, but a hook can be
skipped and does not audit the whole tree.

## 7. Commit discipline

- One intent per commit. A behaviour change and its rule row travel together.
- A change states the `FR` it serves and the `R`/`C` it touches in the commit
  message or the PR note.
- A changed judgement adds a `decisions/` record; a fixed defect adds or updates
  a `rules.md` row and, when the mechanism is new, an `R` row.
- A superseded rule keeps its text and gains `superseded by <ID>`.
- Never commit a real local path, photo title or album name.
