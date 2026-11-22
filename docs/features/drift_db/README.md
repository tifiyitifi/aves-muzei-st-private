# Drift database

The app's single local database: the media catalog, the fork features' tables and
the v2 settings store. Upstream's `LocalMediaDb` interface stays the seam, so the
backing engine can change without callers knowing.

Status: **in progress**. Schema version 18; every upgrade step has a test.

## Scope

In scope:

- one Drift connection per isolate, opened on `<databasesPath>/aves.drift.db`;
- the media domain: entries, dates, metadata, addresses, favourites, covers,
  dynamic albums, vaults, trash, video playback, debug log;
- the fork features' tables (settings values, visible ranges, wallpaper groups
  and history, edit sessions and outputs, batch results and profiles);
- the one-time import of the legacy `metadata.db`;
- forward-only migrations, one `MigrationVN` per schema step, with an upgrade
  test.

Out of scope:

- a second database or ad-hoc SQLite connections (forbidden by `AGENTS.md`);
- regenerating the legacy `metadata.db` (the import is one-way);
- cross-device sync.

## Version facts

| Fact | Value |
| --- | --- |
| Engine | Drift 2.x, `sqlite3` via `sqflite`/`NativeDatabase` |
| File | `<databasesPath>/aves.drift.db` |
| Schema version | 18 |
| Migration steps | v2 .. v18 (v1 is the initial schema) |
| Tables | 24 (`@DriftDatabase` in `app_database.dart`) |
| Provider | `AppDatabaseProvider` (one connection, retried open) |
| Legacy source | `metadata.db`, imported once by `LegacyImport` |
| Codegen | `./flutterw pub run build_runner build --delete-conflicting-outputs` |
| Rule check | `scripts/check-drift-db-rules.ps1` |

## Reading order

1. `spec.md` — persistence requirements.
2. `contracts/schema.md` — the tables and who owns them.
3. `contracts/migrations.md` — the upgrade register, one row per version.
4. `rules.md` — the case register; every row names its evidence.
5. `design.md` — the provider, the migration strategy and the legacy import.
6. `decisions/` — why one connection, why migrations are guarded and forward-only.

## Code map

| Layer | Path |
| --- | --- |
| Database and schema | `lib/features/drift_db/app_database.dart` |
| Provider | `lib/features/drift_db/app_database_provider.dart` |
| `LocalMediaDb` implementation | `lib/features/drift_db/drift_local_media_db.dart` |
| Migrations | `lib/features/drift_db/migration/migration_v*.dart` |
| Legacy import | `lib/features/drift_db/migration/legacy_import*.dart` |
| Domain tables | `lib/features/drift_db/<domain>/` |
| Other features' tables | `lib/features/{meta_settings,visible_range,grouped_wallpaper,refra_edit,batch_ops}/db/` |
| Tests | `test/features/drift_db/` |
| Migration tests | `test/features/drift_db/migration_v*_test.dart` and the owning feature's test directory |

## Privacy note

Every database path in this directory is a stand-in. See `docs/README.md`.
