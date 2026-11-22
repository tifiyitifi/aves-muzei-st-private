# A group with no single survivor shows everything

Status: accepted.

## Context

The policy returns one tile per group, or none. A group backup name can hold two
developed images, two RAWs, or a mix that survived the burst pass.

## Decision

When a group's survivors do not reduce to exactly one representative, every row
maps to itself: nothing hides.

## Why

- With no defensible representative, hiding one of two equals hides a file the
  user cannot reach from the tile.
- Showing both is honest and keeps every file one tap away.
- It gives the policy a total answer (`id -> id | tile`) instead of an error.

## Consequences

- A duplicate developed image is visible twice; that is a catalogue problem, not
  a stacking one.
- The all-null branch also covers the single-row group, where it coincides with
  "this row shows itself".

## Alternatives rejected

- Picking the first anyway: the second file becomes unreachable.
- Refusing to build the group: the caller would have to handle a partial map.
