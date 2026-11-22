# Degrade to a single toggle instead of refusing the gesture

Status: accepted.

## Context

A range cannot be computed when the selection has no anchor, when either end is
missing from the list, or when the user presses the anchor itself. The gesture
could refuse (do nothing) or fall back.

## Decision

Every undeterminable case toggles the pressed row alone, and a press on the anchor
toggles the anchor.

## Why

- A long press that does nothing reads as a broken app; a single toggle is always
  a defensible response to "I pressed this row".
- Missing rows are normal: the list is rebuilt between the press and the
  computation, and filters change what is visible.
- An empty interval is exactly the anchor-pressed case, so folding it into the
  same branch removes a special case.

## Consequences

- The first long press on a non-selecting list starts a selection when the caller
  calls `rangeXorTo` unconditionally (the three list pages rely on this).
- A user who wants to deselect a run cannot use the anchor-pressed path to clear
  it; they tap the rows or range from elsewhere.

## Alternatives rejected

- Refusing with no feedback: indistinguishable from a missed tap.
- Starting a selection at the pressed row when there is no anchor: that is what
  the tap does; the long press should not invent a different origin.
