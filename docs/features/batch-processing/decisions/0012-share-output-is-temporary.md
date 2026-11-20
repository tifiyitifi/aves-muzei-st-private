# 0012 — Share output is temporary and lives in its own folder

Status: accepted (copy & share)

## Context

Copy & share produces files for another app, not results the user has to decide
on. Reusing the batch results table would put share copies in front of the
replace/move-back actions, mix two lifecycles in one query, and make a folder
that is expected to be emptied look like a pending decision list.

The output still has to be visible to other apps: a folder under `Pictures` is
indexed by the MediaStore and can be shared with the normal share action.

## Decision

A share run writes to `Pictures/aves_share`, a sibling of the results root, using
the same job map and the same engine. Nothing is recorded in `batch_results`.

The folder has its own retention (off / 1 / 7 / 30 days, default 7), applied to
its direct children only, and the cutoff uses the file's modified time. Deleting
an expired copy is permanent (`deleteResult`), because a temporary copy in the
recycle bin is noise.

The folder is not pinned and has no results page: the share album is the page.

## Consequences

- The batch table stays a decision list; a share copy is never offered replace or
  move back (`R7`).
- Retention can delete share output without touching a result or a source
  (`R12`, `R14`); capture time would delete a fresh copy of an old photo, so the
  cutoff is the modified time (`C11`).
- A share copy is not a backup, and the folder may be emptied at any time. The
  explainer says so before the first run (`SHR-20`).
- Share output always uses `{name}_{date}`: there is no supersede pass, so a
  plain name would collide across runs (`R15`).
