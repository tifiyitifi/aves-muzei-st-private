# 0001 — A slot id is only valid inside the generation that produced it

Date: 2026-11-21

## Context

The view page, the notification and the effects editor describe the frame on
screen. The renderer can promote a slot without Dart writing, and a background
refill can write a newer `state.json` before the renderer adopts it. Slot ids are
small integers recycled from the smallest free id, so id `3` in generation `G`
can name another photo in generation `G+1`.

The first fixes moved readers from `state.current` to `state.slotById(displayed
slot)`. That works only while both sides are the same generation. When they are
not, the id resolves to the wrong slot, which is the "1→2 works, 3→4 does not,
reopen is fine" complaint.

## Decision

The renderer is the only authority for the displayed frame. `displayedSlot`
returns:

- the drawn slot id and surface;
- the renderer's own state generation;
- the drawn slot's metadata (entry id, uri, title, sharp photo, effects, width,
  height, quarter turns).

Dart builds the slot from that snapshot and injects it for the drawn id. It never
resolves the id against a `state.json` written by another generation. When no
renderer runs, the baked `current` is the fallback.

## Alternatives rejected

- **Poll `reload()` until the generations match.** Adds latency to every view
  open and still guesses when the file moves again.
- **Keep a ring of old `state.json` files.** Doubles the write path for a
  snapshot the renderer already holds.
- **Move every slot's metadata into `runtime.json`.** The renderer would have to
  rewrite the whole queue on every promotion, and Dart would lose the single
  writer of `state.json`.

## Consequences

- The `displayedSlot` channel is a snapshot, not just an id.
- A new reader must not call `slotById` on an id from another source.
- `recurrences.md` R1/R1b and `rules.md` DISP-3/DISP-4 hold the rule.
