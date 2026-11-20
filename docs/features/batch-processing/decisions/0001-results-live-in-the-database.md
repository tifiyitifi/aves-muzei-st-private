# 0001 — A result is actionable only through a database row

Status: accepted (`3c827fe54`)

## Context

A run writes files into a folder. The folder itself cannot say which source a
file came from: a name can collide, a format change can change the extension,
and a user can drop any file into the same folder. Two features that tried to
infer the source from the folder or the name ended up acting on the wrong file:
the copy-first editor listed a staged file twice when two path spellings named
the same volume (`e6c76c8f1`), and a database row that outlived its file kept
offering actions on nothing (`25a3f5a19`).

## Decision

A result is actionable **only** through a `batch_results` row. The row stores the
source URI, the source directory, the current result location and the action
chain. A file in the results folder without a row is never replaced, moved or
deleted by the feature.

## Consequences

- Every file operation is driven by a row, and a row is deleted only after the
  operation succeeded.
- A result deleted from the album leaves a stale row; the page and the banner
  reconcile on open.
- A file another app writes into the folder is inert. That is the intended
  behaviour, not a gap.
- The database becomes a hard dependency of the feature; a corrupt or reset
  database loses the ability to apply old results, though the files remain.
