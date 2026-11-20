# 0011 — Record on `itemDone`, not at the end of the job

Status: accepted (`3c827fe54`)

## Context

The native job reports a terminal `jobDone` with the final counts. Recording the
whole batch there would be simpler: one transaction, one write. But a run can be
cancelled, and an item can fail; by the time `jobDone` arrives the process may
already be gone, and a cancelled run would lose the results it did finish.

## Decision

Record each item when its `itemDone` event arrives. The controller serialises the
writes through a future queue so rows stay in item order, and exposes
`recordsSettled` so a caller that navigates to the results page waits for the
last row.

## Consequences

- A cancelled or interrupted run keeps a row for every result it wrote
  (`R5`).
- A failed item never gets a row (`REC-2`).
- A recording failure is logged and does not fail the run; the file exists
  either way (`REC-6`).
- A caller must await `recordsSettled` before reading the table, because
  `jobDone` can arrive first.
