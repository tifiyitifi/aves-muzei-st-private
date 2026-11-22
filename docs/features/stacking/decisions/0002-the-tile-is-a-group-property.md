# The tile is a property of the whole group

Status: accepted.

## Context

"Which frame shows" could be decided from the rows currently on screen, or from
the whole group in the database.

## Decision

The tile is settled over the entire group at write time, never from the current
view. The view only hides a member while its tile lies in the same predicate
scope.

## Why

- A filter (a tag, a rating, the recycle bin) must not change which frame the user
  sees for the same set of files.
- A view-local choice would move when the user scrolls or filters, which reads as
  flicker.
- The scope rule keeps a member visible when its tile is filtered out, so a
  filtered view never loses a file silently.

## Consequences

- Two views of the same folder always agree on the tile.
- A filter that excludes the tile returns the members, which is why the paged
  window needs the "tile in scope" subquery (`LEN-28`).

## Alternatives rejected

- Choosing the tile from the visible rows: the tile would depend on the filter.
- Hiding a member whose tile is outside the scope: a file would disappear with no
  way to open it.
