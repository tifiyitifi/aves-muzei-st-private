# Only accepted limitations belong in the list

Status: accepted.

## Context

The page is read as "this is how the app behaves". Several limitations have
fixes planned (burst/RAW stacking, the calendar and mosaic layouts), and a
release note or an issue tracker already covers those.

## Decision

An entry describes a limitation the project accepts for good. A planned fix
stays out of the list and lives in `docs/features/*/tasks.md`; the entry is added
only if the fix is abandoned, and removed when the limitation is lifted.

## Why

- A page that mixes "will never" with "not yet" is a roadmap nobody maintains.
- The number of entries is small enough to read; a roadmap would grow it.
- Removing an entry is the visible signal that the limitation is gone.

## Consequences

- Editing the list needs a judgement call, recorded in review, not a test.
- The entry explaining the unsupported-action notice names no specific view,
  because the set of supported views is the part that moves.

## Alternatives rejected

- Marking entries as "planned": the list then needs dates and ownership.
- Linking each entry to a task: published docs must not carry internal ids.
