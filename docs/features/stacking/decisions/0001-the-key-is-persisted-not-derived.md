# The stack key and tile are persisted, not derived per view

Status: accepted.

## Context

A stack needs a key (`<directory>/<burst key>`) and one representative. Both could
be computed in Dart from the loaded rows.

## Decision

The write path stores `baseName`, `stackKey` and `stackTileId` (schema v4) and
keeps them settled; the paged view hides members with one indexed predicate.

## Why

- SQLite cannot reverse-derive a base name (no reverse `instr`), so a query
  cannot group by it without a column.
- The paged view must hide a member without loading the group; an index is the
  only way to do that in one predicate.
- A group decision computed per view could be moved by a filter, which would
  change which frame the user sees.

## Consequences

- Inserts, updates, moves and deletes re-settle the affected groups (`QRY-6`).
- A pattern change rewrites every key, sliced and serialized, and clears the
  tiles before re-settling them.
- The v4 migration backfills the columns for existing rows (`MIG-3`).
- A rebuild failure leaves the groups expanded until the next rebuild; the view
  logs it rather than blocking.

## Alternatives rejected

- Deriving in Dart per view: impossible for the paged query, and filter-dependent.
- Storing a group id instead of a tile pointer: the view would still need a second
  query to find the tile.
