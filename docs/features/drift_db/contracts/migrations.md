# Migrations — the upgrade register

Forward-only. Every step from v2 to v18 owns a `MigrationVN` and an upgrade test
that opens a database at `N-1` and asserts the new shape. v1 is the initial
schema created by `onCreate`.

| Step | Change | Test |
| --- | --- | --- |
| v2 | metadata-settings value table | `test/features/meta_settings/migration_v2_test.dart` |
| v3 | indexed `entry.directory` | `test/features/drift_db/migration_v3_test.dart` |
| v4 | stack index columns and backfill | `test/features/drift_db/migration_v4_test.dart` |
| v5 | visible-range tables | `test/features/visible_range/migration_v5_test.dart` |
| v6 | user-editable preset/rule descriptions | `test/features/visible_range/migration_v6_test.dart` |
| v7 | wallpaper-group table | `test/features/drift_db/migration_v7_test.dart` |
| v8 | group description, rule-usage table, drop sessions | `test/features/drift_db/migration_v8_test.dart` |
| v9 | range base activation flag | `test/features/visible_range/migration_v9_test.dart` |
| v10 | per-group home/lock effects | `test/features/drift_db/migration_v10_test.dart` |
| v11 | per-group interval and ordering, adopting the global ordering | `test/features/drift_db/migration_v11_test.dart` |
| v12 | grouped wallpaper history | `test/features/drift_db/migration_v12_test.dart` |
| v13 | history surface, separate lock range | `test/features/drift_db/migration_v13_test.dart` |
| v14 | one condition pool per group; fold the lock range | `test/features/drift_db/migration_v14_test.dart` |
| v15 | copy-first edit sessions and outputs | `test/features/drift_db/migration_v15_test.dart` |
| v16 | one media-store row per file (merge duplicates) | `test/features/drift_db/migration_v16_test.dart` |
| v17 | batch results and profiles | `test/features/drift_db/migration_v17_test.dart` |
| v18 | collection-aware media-store identity | `test/features/drift_db/migration_v18_test.dart` |

## How the tests build an old database

There is no historical copy of each schema to import. Two patterns are used:

- **Hand-written old shape** (v3, v4, v9, v16–v18): the test creates only the
  tables the step touches, in their old shape, and stamps `PRAGMA user_version`.
- **Rewind the current schema** (`legacy_database.dart`): create the current
  schema, drop the column/table the step adds, stamp the version, then reopen.
  Later steps run too, so the fixture must stay a valid database.

Both open a real file (a temp directory or memory) and force one query so
`onUpgrade` runs before the assertions.

## Invariants

1. A step never deletes user rows it is not replacing; a table rebuild copies
   them.
2. A step guards `addColumn`/`createTable` against an upgrade that already
   passed through it, because SQLite cannot add a column twice.
3. A step that changes a unique key rebuilds the table (SQLite cannot alter it).
4. Data that moved between stores is preserved as the effective value: the
   pre-v11 global ordering becomes every group's ordering, the lock range becomes
   surface-marked pool conditions.
5. The legacy `metadata.db` is never written by a migration; it is imported once
   and left readable.
