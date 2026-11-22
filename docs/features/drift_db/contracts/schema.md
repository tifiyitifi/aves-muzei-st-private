# Schema — tables and owners

One row per table in `@DriftDatabase`. The domain directory owns the table, its
queries and its mapping; `app_database.dart` only aggregates them because Drift
requires one database class.

## Media domain

| Table | Purpose | Owner |
| --- | --- | --- |
| `entry` | one media row: identity, path, size, dates, stack index | `drift_db/entries/` |
| `dateTaken` | resolved date taken | `drift_db/catalog/` |
| `metadata` | catalogued MIME, flags, rotation, subjects, title, coordinates, rating | `drift_db/catalog/` |
| `address` | resolved place for a coordinate | `drift_db/addresses/` |
| `favourites` | favourite marks | `drift_db/favourites/` |
| `covers` | chosen album covers | `drift_db/covers/` |
| `dynamicAlbums` | saved saved-query albums | `drift_db/dynamic_albums/` |
| `vaults` | vaults and their root directories | `drift_db/vaults/` |
| `trash` | trash state and restore details | `drift_db/trash/` |
| `videoPlayback` | resume position per video | `drift_db/video_playback/` |
| `debug` | debug log rows | `drift_db/debug/` |

## Bookkeeping

| Table | Purpose | Owner |
| --- | --- | --- |
| `appMeta` | import/seed markers, pending sync URIs, the shared interval catalog | `drift_db/app_meta/` |
| `settingsValues` | sparse v2 settings overrides with a type tag | `meta_settings/db/` |

## Fork features

| Table | Purpose | Owner |
| --- | --- | --- |
| `visible_range_presets` | saved base presets | `visible_range/db/` |
| `visible_ranges` | one range per scope + owner | `visible_range/db/` |
| `visible_range_rules` | restriction/supplement rules | `visible_range/db/` |
| `visible_range_rule_usage` | which targets a rule was applied to | `visible_range/db/` |
| `visible_range_state` | page view state (active style, last lock preset) | `visible_range/db/` |
| `wallpaperGroups` | one wallpaper group | `grouped_wallpaper/db/` |
| `groupedWallpaperHistory` | photos the grouped wallpaper showed, per surface | `grouped_wallpaper/db/` |
| `refra_edit_sessions` | copy-first edit sessions | `refra_edit/db/` |
| `refra_edit_outputs` | files a session produced | `refra_edit/db/` |
| `batchResults` | finished batch results | `batch_ops/db/` |
| `batchProfiles` | saved batch/share action chains | `batch_ops/db/` |

## Naming

The upstream `metadata.db` used camelCase column names, and the Drift tables keep
them (`createdAt`, `sourceMimeType`, `stackTileId`, ...) so the queries and the
generated code stay compatible with the legacy data and the reference
implementation. `drift_local_media_db_test` pins the names.

## Changing the schema

1. Add or edit the table in its domain directory.
2. Add `MigrationVN` for the step; guard every added column/table so a database
   that upgraded through an earlier step does not add it twice.
3. Bump `AppDatabase.schemaVersion`.
4. Add an upgrade test (`legacy_database.dart` rewinds the current schema).
5. Regenerate `app_database.g.dart` and commit it.
6. Update `contracts/migrations.md` and `rules.md` in the same change.
