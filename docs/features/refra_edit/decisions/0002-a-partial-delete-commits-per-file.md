# 0002 — A partial delete commits per file

Status: accepted.

## Context

Deleting a record removes the file, then the app's entry row, then the output
row. The delete is a stream of per-file events. The first implementation treated
any failure as "nothing happened" and returned before deleting any row, while
the platform may already have deleted some files.

The result was rows pointing at files that no longer existed, and sessions that
could never be pruned because their rows were still complete.

## Decision

Each successful event commits that file's row (entry and output). A failed event
keeps its row and its session so a retry can still find the file. The call
returns whether every file was deleted.

## Consequences

- A locked file keeps its record; the others disappear.
- The session survives a partial delete, which keeps the retry meaningful.
- `clearRecords` still refuses to clear the whole table when a partial delete
  happened, so the surviving rows are not lost behind a "clear all".
