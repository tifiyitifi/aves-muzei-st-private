# 0006 — The results folder is an app album, pinned once

Status: accepted (`3c827fe54`)

## Context

A folder the app writes is not automatically visible. Without a classification
it either appears among the user's photo albums, which misrepresents it, or does
not appear at all. The copy-first editor already hit this: its staging tree was
classified as an app album so the sections view filed it under Apps instead of
with the user's folders (`bc6f41611`).

Pinning is what makes an album appear in the album list. But pinning on every
run would overrule a user who deliberately unpinned the folder.

## Decision

Classify `Pictures/aves_batch_results` as `AlbumType.app`. On the first recorded
result, claim a one-time marker in `appMeta` and pin the folder. A later run
sees the marker and does not pin again.

## Consequences

- The folder groups under Apps and is reachable from the album list after the
  first successful run (`R8`).
- A user who unpins it stays unpinned; the feature never re-adds it (`CLS-6`).
- The marker is written before the pin, so a failure between the two does not
  cause a second pin attempt on the next run.
- The folder is still a normal album: it can be browsed, shared and deleted
  from, like any other.
