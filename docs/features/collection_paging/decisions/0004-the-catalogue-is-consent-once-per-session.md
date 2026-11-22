# 0004 — The catalogue is consent once per session

Status: accepted.

## Context

Cataloguing an existing library is long, invisible work. Starting it silently on
a huge backlog competes with browsing for the device; asking on every visit is
worse. The work is also resumable and the part that remains is just the part not
reached yet.

## Decision

New rows are catalogued inline on sync. A backlog is raised once per session,
only when it is worth mentioning, with three answers: catalogue now, later, or
always. "Later" sweeps nothing and keeps asking on a later session; "always"
stops asking until the choice is reset. A backlog too large to finish during a
visit is handed to the system analysis service when it is available; a small one
runs in the app worker, view scope first, in chunks, resuming from the saved
frontier.

## Consequences

- The prompt cannot become a per-launch nag.
- The app never owns a long sweep it cannot finish; the service keeps working
  while the app is backgrounded.
- A poisoned entry is skipped rather than ending the pass.
- Progress is one monotonic session per pass; a stale owner cannot update it.
