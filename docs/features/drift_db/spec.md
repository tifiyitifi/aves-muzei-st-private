# Drift database — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## One connection

- WHEN two features need the database, THE SYSTEM SHALL share one connection per
  isolate.
- WHEN an open attempt fails, THE SYSTEM SHALL drop the attempt so a later call
  retries.
- WHEN the provider is closed, THE SYSTEM SHALL drop the cached connection so a
  later open reopens.
- WHEN settings initialize before the media import, THE SYSTEM SHALL still read
  the v2 store.

## Schema

- WHEN the schema is generated, THE SYSTEM SHALL keep the upstream camelCase
  column names the queries depend on.
- WHEN a domain table is written and read, THE SYSTEM SHALL round-trip its value.
- WHEN a row is deleted from the database, THE SYSTEM SHALL delete it without
  materializing the library.
- WHEN a directory is renamed, THE SYSTEM SHALL move the folder rows and keep
  their identity.
- WHEN a stack tile is settled, THE SYSTEM SHALL keep one visible tile per group.

## Migrations

- WHEN the schema version is bumped, THE SYSTEM SHALL ship a `MigrationVN` for
  that step.
- WHEN a database opens below the current version, THE SYSTEM SHALL run every
  step in order and reach the current version.
- WHEN an upgrade step finds the column or table already present, THE SYSTEM
  SHALL skip it instead of failing.
- WHEN an upgrade step must change a unique key, THE SYSTEM SHALL rebuild the
  table and copy the old rows.
- WHEN an upgrade adds a feature table, THE SYSTEM SHALL leave existing rows
  untouched.
- WHEN an upgrade moves user data, THE SYSTEM SHALL preserve the user's effective
  value.

## The legacy import

- WHEN a legacy database exists, THE SYSTEM SHALL import every table once, keep a
  backup and leave the legacy file readable.
- WHEN the app has no legacy file, THE SYSTEM SHALL mark the import done without
  creating one.
- WHEN an import is interrupted, THE SYSTEM SHALL resume from the last committed
  chunk.
- WHEN another actor owns the import, THE SYSTEM SHALL wait instead of starting a
  second.
- WHEN verification finds a mismatch, THE SYSTEM SHALL reconcile from a clean
  slate.
- WHEN the persisted cursor is corrupt, THE SYSTEM SHALL restart instead of
  bricking the import.

## Generated code

- WHEN a table, migration or column changes, THE SYSTEM SHALL regenerate and
  commit the generated file.
- WHEN the generated schema is missing, THE SYSTEM SHALL fail the build rather
  than run against a stale schema.
