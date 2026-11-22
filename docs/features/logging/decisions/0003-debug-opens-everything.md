# Debug opens everything, release opens nothing

Status: accepted.

## Context

The fork runs on devices the developer does not own, and a release build that
logs every media path is both noisy and a privacy problem. A build that logs
nothing is undiagnosable.

## Decision

A debug build opens every shared channel at `verbose`. A release build opens
nothing by default; opening a channel in release surfaces `warning` and above.
`AVES_LOG_KEYS` overrides either default, last.

## Why

- Debug is the development loop: a dropped log there is a bug in the app.
- Release output is a cost (battery, log buffer, privacy), so it is opt-in.
- Warning and error are the levels worth a release channel: they describe a
  failure, not a trace.
- The define is applied last so a locally opened channel is never overridden by
  the build default.

## Consequences

- `Log.isEnabled` on a release build answers `false` until a channel is opened,
  which is what guards expensive message construction.
- The Logcat mirror only exists for those release warnings and errors.

## Alternatives rejected

- Opening every channel in release: the log buffer fills with media paths.
- A release gate of `info`: still a trace, still a privacy surface.
