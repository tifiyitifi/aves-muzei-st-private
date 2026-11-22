# 0003 — The library phase moves one way

Status: accepted.

## Context

A first launch has to choose between two surfaces: the browse-only browser
(while the database is being filled) and the collection. The app used to answer
that question in several places, from different signals: a per-lens flag, the
transient import status, and a preference that is false until it is loaded. A
frame of disagreement is enough to swap the grid for the browser and back.

## Decision

`LibraryPhase` is the single answer. It moves one way: once `ready`, only a new
install or a database reset brings browsing back. New photos arrive through the
collection's own sync and never touch it. The phase is persisted with the
completion flag, and a reset database clears it.

## Consequences

- No surface may answer "is the library whole" from its own state.
- A failed import keeps browsing and clears the phase only on retry.
- A completion flag written too early would hide the rest of the library, so it
  is written after the import ends, not after the first batch.
- The browse-only bar and the browse-only action locks follow the same phase.
