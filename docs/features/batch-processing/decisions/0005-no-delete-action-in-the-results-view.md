# 0005 — The results UI has no delete action

Status: accepted (`3c827fe54`)

## Context

The results page is a list of files, and a list of files usually offers delete.
But the results folder is a normal album: the collection's multi-select already
deletes files, honours the recycle-bin setting and the confirmation policy, and
works for every other album. A second delete path would duplicate that policy
and diverge from it.

## Decision

The batch results UI offers three decisions only: replace the original, move the
result back, or leave it pending. It has no delete action.

## Consequences

- Deleting a result is ordinary album browsing; the feature does not
  special-case it.
- A deleted result leaves a stale row; the page and the banner reconcile on open
  and drop it (`HOU-1`).
- The results page stays a decision surface, not a file manager.
- A user who wants a result gone without applying it deletes it in the album,
  which is discoverable and already understood.
