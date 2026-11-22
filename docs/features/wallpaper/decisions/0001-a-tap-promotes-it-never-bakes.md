# 0001 — A tap promotes, it never bakes

Status: accepted.

## Context

Muzei's tap is a texture swap: the renderer draws the artwork that is already
decoded. A bake decodes, crops, applies effects, encodes three PNGs and writes
them — hundreds of milliseconds. Doing that on the tap gesture would make every
tap feel broken, and a burst of taps would queue bakes instead of changing the
wallpaper.

## Decision

Dart keeps one or two spare slots (`next`, `next2`) fully baked. A tap asks the
renderer to promote the next spare and records that promotion in
`runtime.json`. The refill then bakes a new spare. When no app engine is
attached, the native worker starts the headless refill instead, so a tap still
works after the app is closed.

A bake that races a tap must not commit `current` from a snapshot taken before
the tap; it writes only the spare it was producing.

## Consequences

- Taps are instant up to the spare depth; beyond that they are buffered.
- Two spares cost one extra slot (roughly 13 MB of PNGs on a 1080p phone) and
  one extra artwork in every effect rebake; the depth is a setting.
- `runtime.json` is written by the renderer, not Dart, which is why the
  generation is part of the state contract.
- A tap burst that outruns the refill is replayed one per prefetch instead of
  being dropped.
