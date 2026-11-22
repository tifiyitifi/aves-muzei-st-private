# Drift database — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Database tests | `.flutter/bin/flutter.bat test test/features/drift_db` | do the provider, queries and migrations hold |
| Feature migration tests | `.flutter/bin/flutter.bat test test/features/meta_settings/migration_v2_test.dart test/features/visible_range/migration_v5_test.dart test/features/visible_range/migration_v6_test.dart test/features/visible_range/migration_v9_test.dart` | do the steps owned by other features hold |
| Codegen | `.flutter/bin/flutter.bat pub run build_runner build --delete-conflicting-outputs` | is the committed schema current |
| Rule register | `pwsh -NoProfile -File scripts/check-drift-db-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does a real upgrade keep the library |

## The sqlite requirement is load-bearing

`flutter test` runs on the host VM without the plugin bundling step, so
`sqlite3_flutter_libs` supplies nothing there. `test/helpers/sqlite3_loader.dart`
fails loudly instead of skipping. Point `AVES_SQLITE3_DLL` at a full native
build (see `AGENTS.md`). Do **not** use the Microsoft `winsqlite3.dll`: its
`localtime` modifier is broken, so month/day section queries return nothing and
the paged lens blocks (77 collection-paging tests fail).

## How a migration is tested

Two patterns, both real upgrade paths:

- **Hand-written old shape** — create only the tables the step touches in their
  old shape and stamp `PRAGMA user_version`. Used by v3, v4, v9 and v16–v18,
  where the old fixture is small.
- **Rewind** — `test/features/drift_db/legacy_database.dart` creates the current
  schema, drops the object the step adds, stamps the version, closes, and reopens
  an `AppDatabase` on the same file. Used by v7, v8, v10–v15.

Both force one query (`SELECT 1`) so `onUpgrade` runs before assertions. Assert
the version reached `db.schemaVersion`, the new column/table exists, and the
user-visible value the step was supposed to preserve (ordering, folded base,
surface, description).

Adding a migration without this test fails the register: every `MIG-n` row names
its file.

## Device checklist

1. Install an older build, create albums, favourites and a visible range, then
   install the current build over it. Expect the library, the range and the
   settings to survive. (`MIG-1`..`MIG-17`, `LEG-1`)
2. Upgrade a library large enough for the first import to take minutes; kill the
   app mid-import and relaunch. Expect it to resume and not duplicate rows.
   (`LEG-3`, `LEG-8`)
3. Delete the app's data, relaunch. Expect a fresh database with no legacy import
   and a working settings page. (`LEG-2`)
4. Rename a stored album folder, then open the album. Expect the rows and the
   album counts to follow. (`QRY-8`)

## Privacy

Never copy a real database file or a media title into a fixture or a note.
