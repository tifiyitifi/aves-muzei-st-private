# 0007 — Copy & share reuses the engine, separated by the output path

Status: accepted (`3c827fe54`, not implemented)

## Context

The next feature is copy & share: process a selection, then hand the output to
another app. It needs the same tools, the same chain, the same profiles and the
same partial-completion behaviour as batch processing. A second engine would
duplicate the native registry, the bake path and the failure handling.

It must not share the batch result table: share output is temporary, gets a
retention policy, and is not a candidate for "replace the original".

## Decision

Copy & share runs the same engine and the same `BatchRunController`, with a
different `BatchOutput.relativePath`. The recorder accepts an item only when the
output spec is exactly the batch results folder, so a share run records nothing.
Share profiles live in the same `batch_profiles` table with `kind = 'share'`.

## Consequences

- One engine, one bake path, one cancellation policy.
- The output path is the boundary (`I6`); relaxing the recorder gate would mix
  the two features (`R7`).
- Share output can have its own retention without touching batch results.
- The two entry points can diverge in UI without diverging in behaviour.
