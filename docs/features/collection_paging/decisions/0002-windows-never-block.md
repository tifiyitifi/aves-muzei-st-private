# 0002 — Windows never block

Status: accepted.

## Context

A windowed list has one hard constraint: a frame cannot wait for the database.
The obvious implementation (await the rows for the visible range) turns every
fling into a stutter, and a slow query into a frozen frame.

## Decision

`WindowCache` answers `peek` from memory or null. A miss schedules a fetch for
that window plus bounded neighbours and returns. Rapid misses coalesce into one
batch around the destination the fling settles on. `invalidate` bumps a
generation, and completions from an older generation are dropped.

## Consequences

- The grid paints a skeleton tile instead of blocking, and fills in on the next
  frame.
- A fling costs one query batch, not one per crossed window.
- A stale completion can never splice rows from a previous scope into the
  current view; that is the half of the invariant that is easy to lose.
- Callers must tolerate a null window, which is why lookups materialize exactly
  one row instead of loading a window.
