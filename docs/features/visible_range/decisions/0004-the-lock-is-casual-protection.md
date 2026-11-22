# 0004 — The lock is casual protection

Status: accepted.

## Context

A user may want to browse a narrowed range without accidentally deleting,
moving or editing what they see, or without handing an unlocked device to
someone who would. The app already has a vault for real privacy; a second
security boundary would be misleading.

## Decision

A locked range carries a permission preset (`readOnly`, `manageable`, `full`).
The gate withholds the mutations the preset does not list, for the browsing
session. The lock is described in the UI as casual protection inside Aves, and it
does not encrypt, hide or authenticate anything.

## Consequences

- The check is one predicate (`VisibleRangeGate.allows`) that every action calls.
- Unlocking restores every operation and drops the stale permission set.
- The lock protects the library surface, not the files: another app or a direct
  file manager is unaffected. That is consistent with the vault being the real
  privacy feature.
