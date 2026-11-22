# A failed read keeps what it already has

Status: accepted.

## Context

The browser reads in pages. A page can fail (timeout, provider error) after the
previous ones succeeded.

## Decision

A failed page keeps the rows already read, records the error, and stops automatic
paging. A retry clears the error and resumes from the last cursor. The album list
and the album page follow the same rule.

## Why

- Losing a readable window because the next page failed is worse than a shorter
  window with a retry.
- Stopping auto-paging prevents a failing provider from being hammered by scroll
  events.
- Resuming from the last cursor continues the walk instead of re-reading it.

## Consequences

- The view must render "what I have plus an error", not one or the other.
- A timeout is a distinct, retryable error, because a lost platform reply is the
  common failure.
- The window exposes `error`, `hasMore` and `retry` so the view can offer the
  action.

## Alternatives rejected

- Clearing the window on error: the user loses visible tiles.
- Retrying automatically: a failing provider would spin.
