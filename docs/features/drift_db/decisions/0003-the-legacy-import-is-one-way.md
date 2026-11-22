# 0003 — The legacy import is one way

Status: accepted.

## Context

Upstream stored the catalog in `metadata.db` (sqflite). The fork moved to Drift
for windowed queries. Existing installs already hold a full catalog there, and
users upgrading must not rescan or lose favourites, covers and albums.

## Decision

`LegacyImport` reads `metadata.db` once, in chunks, commits a cursor per chunk,
keeps a backup and leaves the original file readable. A marker in `appMeta` makes
it one-shot. A fresh install marks it done without creating a legacy file. The
fork never writes `metadata.db`.

## Consequences

- An upgrade keeps the whole catalog without a rescan.
- A kill mid-import resumes; a corrupt cursor restarts instead of bricking.
- The legacy file remains as a fallback for a user who rolls back to an older
  build.
- Two actors cannot import at once; the second waits.
- A verification mismatch reconciles from a clean slate rather than leaving a
  half-imported table.
