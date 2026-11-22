# `off` is a gate value, never a record level

Status: accepted.

## Context

The level enum is shared by two questions: "which levels does this channel
pass?" and "what is this record's severity?". A closed channel needs a value
that sits above every real level so the comparison `severity >= gate` reads
naturally.

## Decision

`LogLevel.off` (2000) is the closed-channel sentinel. `isEnabled` reports `false`
for it even when the channel is open, and `emit` never forwards it.

## Why

- One comparison resolves an open gate; `off` needs no special case in
  `_gateFor`.
- Without the guard, `isEnabled(key, off)` would be `true` on an open channel and
  a caller could emit a "record" that means "disabled".
- `_gateFor` returns `off` for an unconfigured channel, so the sentinel is also
  the natural default.

## Consequences

- A call site that passes `off` is a no-op, tested from both sides (open and
  closed channel).
- The numeric value must stay above `error`; adding a level below 2000 is safe,
  adding one at 2000 is not.
