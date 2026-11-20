# 0013 — A share run does not open the share sheet

Status: accepted (copy & share)

## Context

The obvious end of a "copy & share" flow is the system share sheet. But a run is
not all-or-nothing: some items can fail while others are written, and the sheet
would hide which ones exist. The user may also want to review the copies, pick a
subset, or run the chain again before sending anything.

The sheet is a one-shot Intent payload: it cannot represent a folder that is
still being scanned, and it would turn a completed run into a modal interruption.

## Decision

A run ends with a snackbar that reports how many copies are ready and offers
VIEW. VIEW opens the share album, where the normal multi-select share action
sends whatever the user picks. No system share sheet is opened automatically.

## Consequences

- Partial completion stays visible: the album shows exactly the files that were
  written, and the snackbar count matches them (`SHR-19`).
- Sharing is the same action as for any other album, so it inherits the app's
  share behaviour and the range/selection rules.
- One extra step for the common "send everything" case; the snackbar makes it a
  single tap.
- The share folder must be reachable on its own, which is why it is an app album
  and the snackbar links to it.
