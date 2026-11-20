# 0009 — v1 has no undo history

Status: accepted (`3c827fe54`)

## Context

Replacing an original is destructive. An undo would need the original bytes kept
somewhere, a history table, a retention policy and a conflict story for a source
that changed after the replacement. None of that exists yet, and the feature is
already large.

The non-destructive path already exists: move the result back instead of
replacing, and the original stays untouched.

## Decision

v1 has no undo or redo for an applied result. The confirmation dialog states
that replacing cannot be undone. The results table keeps no tombstone.

## Consequences

- Replacing is a deliberate, confirmed action with no safety net.
- The Known Issues section states that results are not a backup
  (`aboutKnownIssues7`).
- Move back is the safe alternative and is offered beside replace.
- A future undo would need a new decision, a storage policy and a migration; it
  is not a UI addition.
