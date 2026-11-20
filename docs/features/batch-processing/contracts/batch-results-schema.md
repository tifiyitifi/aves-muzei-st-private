# Batch results schema (v17)

Schema version 17 adds two tables. The migration creates them and their indexes;
it rewrites no existing row. A v16 database upgrades in place, and a fresh
install creates the same shape (`SCH-1`, `SCH-2`).

Owner: `lib/features/batch_ops/db/batch_result_tables.dart`
Migration: `lib/features/drift_db/migration/migration_v17.dart`

## `batch_results`

One row per file the feature wrote into the results folder.

| Column | Type | Null | Default | Meaning |
| --- | --- | --- | --- | --- |
| `id` | TEXT | no | — | `${jobId}-${index}`, primary key |
| `jobId` | TEXT | no | — | the run that produced it |
| `sourceEntryId` | INTEGER | yes | — | Aves entry id at run time; informational, ids churn |
| `sourceUri` | TEXT | no | — | source content URI |
| `sourcePath` | TEXT | no | `''` | source absolute path, empty when unknown |
| `sourceDirectory` | TEXT | no | `''` | where move back would put the file |
| `sourceName` | TEXT | no | — | source file name at run time |
| `resultUri` | TEXT | no | — | current content URI of the result |
| `resultPath` | TEXT | no | `''` | current absolute path |
| `resultFileName` | TEXT | no | — | current file name |
| `resultMimeType` | TEXT | no | `''` | current MIME type |
| `resultSizeBytes` | INTEGER | no | `0` | current size |
| `actionsJson` | TEXT | no | `''` | the action chain that produced it |
| `createdAt` | INTEGER | no | — | epoch milliseconds |
| `status` | TEXT | no | `'pending'` | `pending`, `applied` or `discarded` |

Indexes:

- `idx_batch_results_source_uri` — supersede lookup by source.
- `idx_batch_results_status` — pending queries.
- `idx_batch_results_created_at` — newest-first listing.

## `batch_profiles`

A saved action chain, separated by the kind of run it belongs to.

| Column | Type | Null | Default | Meaning |
| --- | --- | --- | --- | --- |
| `id` | TEXT | no | — | primary key |
| `name` | TEXT | no | — | user name; empty means the localized default |
| `actionsJson` | TEXT | no | `'[]'` | the chain, including disabled rows |
| `kind` | TEXT | no | `'batch'` | `batch` or `share` |
| `sortOrder` | INTEGER | no | `0` | display order |
| `isActive` | BOOLEAN | no | `0` | the profile a run starts from |
| `createdAt` | INTEGER | no | — | epoch milliseconds |
| `updatedAt` | INTEGER | no | — | epoch milliseconds |

Index:

- `idx_batch_profiles_kind` — listing one kind.

## Migration

`MigrationV17.run` calls `createTable` for both tables, then
`createNewIndexes`. The same `createNewIndexes` runs on a fresh database, so an
upgrade and a fresh install cannot drift.

The migration is forward-only and has no data step: v16 has no batch rows to
convert.

## Semantics

- **The row, not the folder, is the source of truth.** A file in the folder
  without a row is never replaced, moved or deleted by the feature (`I2`).
- `status` is written as `pending` at record time. v1 deletes the row when a
  result is applied or gone; `applied` and `discarded` are rendered but not
  written. See `design.md` §11.
- `resultUri`, `resultPath`, `resultFileName`, `resultMimeType` and
  `resultSizeBytes` describe the file's **current** location. A rename or move
  rewrites them (`REC-8`).
- `sourceUri` and `sourceDirectory` are a snapshot of the run. A later move of
  the source does not update them.
- `actionsJson` is the same JSON a profile stores, so a result is explainable
  after the sheet is gone.
- `kind` is the join key between the profile store and a run kind. Copy & share
  adds rows of `kind = 'share'`; it does not add a table (`PRF-2`, `C9`).
