# 0001 — One connection for settings and media

Status: accepted.

## Context

The v2 settings engine stores its overrides in the same Drift database as the
media catalog. Settings also initialize before the media import runs, because
every page reads settings on its first frame.

Opening the database twice (once for settings, once for the media DB) would give
two writers, two migration runners and two file handles for one file.

## Decision

`AppDatabaseProvider` opens one `AppDatabase` lazily, memoizes the future and
hands the same connection to `DriftLocalMediaDb` and `MetaSettingsStore`. Opening
is split from the media import so settings can read before the import runs. A
failed open is dropped and retried; `close()` clears the cache.

## Consequences

- One writer and one migration runner per isolate.
- Settings are available on the first frame, before the catalog import.
- A feature that needs the database must go through the provider; opening a
  second `NativeDatabase` is an anti-pattern.
- A transient open failure retries instead of poisoning the process.
