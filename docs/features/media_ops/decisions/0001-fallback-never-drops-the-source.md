# 0001 — A fallback that cannot read the source never drops it

Status: accepted.

## Context

The SAF fallback copies a source into a new target, then deletes the source when
the operation is a move. `StorageUtils.openInputStream` returns `null` for a
source that is pending, revoked or otherwise unreadable, and the insert helpers
still create their target when the write callback writes nothing. The sequence
therefore produced a 0-byte target and then deleted the real source.

## Decision

The source stream is opened before the target exists. A null stream throws, so
the item fails, the target is never created and the source is never deleted.

## Consequences

- A pending or revoked source fails loudly instead of losing its bytes.
- The operation reports the item as failed; the user can retry after the other
  app finishes writing.
- A partially written target from a mid-copy failure is left for the next scan
  to prune, but the source is still intact.
