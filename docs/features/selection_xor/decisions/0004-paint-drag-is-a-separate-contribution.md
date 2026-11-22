# Paint-drag is a separate contribution from the flip

Status: accepted.

## Context

A long press both starts a range and starts a paint drag (moving the finger over
rows adds or erases them). The two could be unified into one "paint what I
crossed" loop.

## Decision

The long press settles the XOR flip once, then the drag paints from the pressed
row with the existing additive/erase logic. The drag never consults the anchor.

## Why

- The flip answers "what did this gesture cross before it started painting"; the
  drag answers "what am I painting now".
- Unifying them would double-flip the pressed row on the first paint step, because
  the flip already includes the target.
- Reversing a drag already un-paints the rows it crossed; that is the drag's own
  inverse and does not need the anchor.

## Consequences

- The gesture detector records the pressed row and index for the drag separately
  from the anchor.
- A paint drag that starts from a range's target cannot "un-range" the interval;
  the user ranges again instead.

## Alternatives rejected

- One unified gesture: the first painted row would flip twice.
- Disabling paint after a range: loses the fast way to extend a selection.
