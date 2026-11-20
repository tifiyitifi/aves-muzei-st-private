# 0002 — A run never modifies an original

Status: accepted (`0bd4476aa`)

## Context

The batch engine reuses the built-in editor's adjustments and bake path. The
editor already works on a staged copy, because devices and third-party editors
disagree on whether saving overwrites the source or writes a new file
(`c23a4d38d`). A batch run has the same problem at a larger scale: a crash, a
cancelled run or a bad chain would damage many originals at once.

## Decision

A run writes every output below the results folder and never writes a source.
Replacing an original is a separate, explicit action on a recorded result.

## Consequences

- A run is non-destructive by construction; the only destructive operations are
  replace and the permanent delete of a consumed or superseded result.
- The feature needs disk space for the results; a run doubles the bytes it
  processes.
- Results need a decision. That is why the results folder, the banner and the
  results page exist.
- Cancellation is safe: the items already written stay, and no source is
  half-written.
