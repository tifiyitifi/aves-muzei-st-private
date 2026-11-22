# 0005 — Sync advances the cursor last

Status: accepted.

## Context

The MediaStore generation is a single cursor. When it moves, the app fetches only
the changed URIs. A change that fails (a transient provider error, a file still
being written) would be lost forever if the cursor advanced anyway: the next sync
would start after it.

## Decision

A changed URI that cannot be settled is written to `pending_sync_uris` and
retried with the next sync. The list is persisted **before** the generation
cursor advances; if the list cannot be persisted, the cursor stays put and the
same change is offered again.

## Consequences

- No change is lost to a transient failure.
- A permanently broken URI keeps its slot in the retry list; the sync reports it
  instead of silently dropping it.
- The obsolete check is settled once for the whole change set, so a failed batch
  does not turn into one platform call per row.
- The order (rows, retry list, cursor) is the invariant; reordering it is how
  this bug would return.
