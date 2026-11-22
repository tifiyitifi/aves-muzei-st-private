# The interval is an XOR flip, not a select-from-to

Status: accepted.

## Context

Multi-select needs a "pick this run" gesture. The obvious implementation is
"select every row between A and B". With that rule, a second range has to know
what the first one selected in order to undo it.

## Decision

A range flips the rows between the anchor and the target: selected rows become
unselected, unselected rows become selected. The anchor is excluded, the target is
included.

## Why

- The interior of `A -> B` is the same set as the interior of `B -> A`, so ranging
  back is the undo.
- Repeated ranges compose without a history: each one is its own inverse on the
  rows it crosses.
- The two endpoints keep their state, so a run never loses the row the user
  started from or the row they pressed.

## Consequences

- The gesture needs an anchor; a selection with no order (a declared mark) cannot
  start a range.
- A range over an already-selected run deselects it, which is the intended way to
  trim a selection.
- The anchor moves to the target after the flip, so the next range starts where
  the user last pressed.

## Alternatives rejected

- Select-from-to: undoing a range would need a snapshot of the previous
  selection.
- Toggle-only (no range): the gesture this feature exists to remove.
