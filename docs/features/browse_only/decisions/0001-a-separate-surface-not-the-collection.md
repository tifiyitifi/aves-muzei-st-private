# A separate surface, not the collection with filters applied

Status: accepted.

## Context

While the one-time import builds the database, the collection has to answer from a
partial store. It could show partial answers, fall back to an empty state, or a
different surface could answer from MediaStore.

## Decision

The browser is its own surface with its own data path (MediaStore paging) and its
own views. It is not the collection with a filter that says "importing".

## Why

- Every attempt to make the collection answer earlier leaked half-built answers
  into the UI: a folder list missing albums, counts growing between frames.
- MediaStore is the complete library; a separate reader has no half state.
- Keeping the two surfaces apart means the handoff is one phase change, not a
  series of partial states.

## Consequences

- The browser has no selection, no editing and no metadata-dependent actions; the
  bar greys them instead of emulating them.
- Some presentation is duplicated on purpose (tile extent, month sections) so both
  surfaces read the same without sharing code paths.
- A new library action must decide whether the browser can serve it.

## Alternatives rejected

- Partial collection answers: users see a folder list that changes under them.
- An empty state until the import finishes: the app is unusable for minutes.
