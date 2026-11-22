# 0005 — The state files are the contract

Status: accepted.

## Context

Dart owns the photo pipeline; the native renderer owns textures, crossfades,
focus, offsets and gestures. Neither can do the other's job, and the renderer may
promote a slot while Flutter is not running. The two sides therefore need a
durable, atomic description of what is on disk and what is being drawn.

## Decision

`state.json` is Dart-owned: slots, `current`/`next`/`next2`, recent artworks,
effects, gestures, ordering, target and a `generation` counter.
`runtime.json` is native-owned and records the slot the renderer promoted. Slot
PNGs and `art.json` sit under `slots/<id>/`, written through `tmp/` and renamed.

A slot id is valid only inside the generation that produced it. A runtime whose
generation matches is authoritative for what is on screen; a mismatched runtime
is stale. Every write goes through the store's file lock and a temp-file rename.

## Consequences

- The renderer can advance without Flutter, and the next Dart adoption reads
  `runtime.json` instead of rebaking.
- A reader must carry the generation with the slot id; resolving an id against a
  newer state is the recurring display bug (`R1`).
- The file lock is what lets the foreground page and a background refill share
  the directory safely.
- A format change is a state-version bump; an unknown version reads as absent
  rather than half-applied.
