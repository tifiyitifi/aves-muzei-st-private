# 0002 — One refusal is not a provider limitation

Status: accepted.

## Context

`updateMediaStoreName` tries a row update with `TITLE`, then without it. The
combined result was `UNSUPPORTED` when either attempt was `UNSUPPORTED`, and the
caller disabled the Media Store path for the rest of the whole batch. A
temporary permission refusal in the fallback attempt was enough to trigger that.

## Decision

Only when both shapes are `UNSUPPORTED` does the provider lack the capability.
Otherwise the result is `REFUSED`, which falls back for this entry only.

## Consequences

- A single refused entry does not push the rest of the batch onto the slow path.
- A provider that genuinely cannot rename rows still disables the fast path, so
  the batch does not retry it per entry.
