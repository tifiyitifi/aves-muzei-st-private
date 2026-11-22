# The anchor lives in `Selection`, as an item compared by key

Status: accepted.

## Context

A range needs a remembered origin. It could be an index or an item, and it could
live in the page, the grid, or the selection model.

## Decision

`Selection` owns the anchor as an item (`T?`), compares it with `isSameItem`
(`keyOf`), and moves or drops it in its own methods. Call sites pass only the
visible ordered items.

## Why

- A page-owned anchor goes stale when the page is rebuilt or two grids share a
  selection; the model is the only object that sees every toggle.
- An index is invalid as soon as the list is rebuilt from a database read, which
  is the normal refresh path.
- An item compared by key survives fresh instances of the same row.

## Consequences

- `toggleSelection` moves the anchor on every toggle, including a deselecting tap.
- `browse`, `clearSelection` and `markAll` drop it; `addToSelection` does not move
  it.
- A test that ranges must assert the anchor's key, not the object's identity.

## Alternatives rejected

- Per-page anchor: duplicates the rule and drifts.
- Index anchor: silently targets a neighbour after a refresh.
