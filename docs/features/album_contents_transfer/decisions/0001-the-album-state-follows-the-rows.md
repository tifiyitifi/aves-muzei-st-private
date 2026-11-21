# 0001 — The album state follows the rows

Status: accepted.

## Context

A native folder rename moves the files first. The Dart side then rewrites the
stored paths and moves the album state (cover, group membership, pin, bookmarks,
vault metadata). The two steps can fail independently: the folder is gone, but
the database update may hit a busy or read-only database.

Advancing the state anyway pointed every album-level reference at a directory
whose rows never arrived, while the rows still named the old one.

## Decision

The album state is moved only when the row rewrite succeeded. A failed rewrite
is logged and the action reports failure; the next scan or sync re-reads the
paths.

The batched fallback has the same rule: `doQuickMove` returns true even when
every item failed, so the caller counts the moved entries and moves the state
only for a non-zero count.

## Consequences

- A transient database failure leaves the album under its old name rather than
  attaching it to a folder with no rows.
- The user sees a warning; a later scan converges the rows.
- The native folder rename is not rolled back, because the platform has already
  moved the files and does not expose an atomic undo.
