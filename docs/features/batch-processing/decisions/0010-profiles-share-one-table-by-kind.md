# 0010 — Profiles share one table, keyed by kind

Status: accepted (`3c827fe54`)

## Context

A profile is a named action chain. Batch processing and copy & share need the
same shape: the same tools, the same JSON, the same active-profile rule. Two
tables would duplicate the store, the queries and the migration.

## Decision

One `batch_profiles` table with a `kind` column (`batch` or `share`). Every query
filters on the kind. The seed creates one default per kind.

## Consequences

- Adding a run kind adds rows, not a table (`C9`).
- A profile cannot leak between the two entry points; the kind is part of every
  read.
- A profile holds the chain including disabled rows, so re-enabling a row later
  does not require re-creating the profile (`PRF-6`).
- The default profile's name is stored empty; the view resolves the localized
  name, so the database never stores a translated string.
