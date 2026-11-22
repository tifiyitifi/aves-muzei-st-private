# Persist the span, never the resolved instant

Status: accepted.

## Context

A relative window ("the last 7 days") can be stored as the span or as the two
instants it resolves to. It appears in search filters and in the shipped
visible-range presets.

## Decision

Persist the span token (`7d`); resolve the cutoff when the filter is constructed
and never persist it.

## Why

- A preset must keep meaning "the last 7 days" every time it is applied.
- A stored instant would age: a preset saved last month would select nothing.
- Equality by span means a restored filter dedupes with the one it came from.

## Consequences

- `RelativeTimeFilter.reverse()` round-trips through JSON and re-anchors, so the
  two instances can have cutoffs minutes apart; each SQL fragment uses its own
  filter's cutoff.
- A corrupt token drops the filter instead of raising.

**Update:** `reverse()` now keeps the cutoff; see
[`0005`](0005-the-reversal-keeps-the-anchor.md).

## Alternatives rejected

- Storing both bounds: simple to compare, but a saved filter silently becomes a
  fixed date range.
- Storing a resolved instant plus the span: two sources of truth for one window.
