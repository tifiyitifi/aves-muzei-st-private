# One snapshot blob in shared preferences, not a setting

Status: accepted.

## Context

The app needs to remember one page across a process death. The project has three
persistence surfaces: `Settings` (shared preferences through a store), the
settings engine (Drift), and the media database.

## Decision

Store the snapshot as one JSON string under one shared-preferences key, outside
`SettingsStore`, the settings router and the database.

## Why

- A snapshot is a session artifact: it is overwritten every pause and cleared on
  back-out, so it needs none of the settings engine's history, defaults or
  migration.
- The `settings_engine` gate switches between two stores; a session artifact
  should not change owner when the user flips that switch.
- Clearing is one `remove`, and the whole record is replaced atomically.

## Consequences

- The snapshot has no schema version; unknown keys are ignored and a renamed key
  reads as absent. A rename would silently drop that field, so a field must be
  added, not renamed.
- Tests inject a `prefsProvider`, which keeps the slice independent of the
  settings fixtures.

## Alternatives rejected

- A settings key: it would be seeded, exported and gated like a preference.
- A database row: heavier, and it would outlive the install's intent.
