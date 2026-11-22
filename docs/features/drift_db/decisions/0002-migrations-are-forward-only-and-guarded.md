# 0002 — Migrations are forward-only and guarded

Status: accepted.

## Context

The fork grew from an empty schema to version 18 in a few weeks, with features
adding tables and columns in parallel. SQLite has no transaction around a schema
upgrade that survives a crash, no `ADD COLUMN IF NOT EXISTS`, and cannot alter a
unique constraint.

A step that assumes it is the only one changing a table fails on an install that
passed through a later definition first.

## Decision

- Every step is a small `MigrationVN`; the version only moves forward.
- Structural changes are guarded by `PRAGMA table_info` / `sqlite_master`, because
  a database upgrading from an earlier version may already have the column or
  table through a later step's current definition.
- A unique-key change rebuilds the table and copies the rows (v13).
- Data that moves between stores keeps its effective value (v11 ordering, v14
  folded lock range).
- Every step ships with an upgrade test; `AGENTS.md` forbids a version bump
  without one.

## Consequences

- An upgrade from any older version works, including a big jump.
- A test can create a minimal old shape and still exercise the step, because the
  step guards what is missing.
- A broken step is caught by its own test instead of a device crash.
- Generated code is part of the schema; it must be regenerated and committed.
