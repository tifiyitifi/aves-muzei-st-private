# The match count describes the grid, not the table

Status: accepted.

## Context

The "more filters" sheet previews how many entries a draft condition matches. The
obvious implementation counts the compiled predicate over the entry table, but the
grid hides more than the table does: the active visible range, the user's hidden
albums, locked vaults and stack members.

## Decision

The counter composes the same predicate the paged window resolves: the visible
range, hidden filters, locked vault directories and the stack filter. If any of
that cannot be expressed in SQL, it reports no count instead of falling back to a
whole-library scan.

## Why

- A preview that exceeds the result teaches the user to distrust the count.
- Counting stack members twice is the most visible mismatch: a burst of ten frames
  would read "10" and show one tile.
- A locked vault keeps its rows in the database, so the exclusion has to come from
  the predicate, exactly as in browsing.

## Consequences

- The count is a tile count, so the calendar layout (which groups by day) can show
  more rows than the number; the sheet describes the default grid.
- The predicate builder is shared with the paged lens (`withStackFilter`), so the
  two cannot drift.
- The count stays advisory: any failure reports `null`.

## Alternatives rejected

- Counting the raw table: fast, but the number would not match anything the user
  can see.
- Counting through the lens: it needs a resolved window and a full collection.
