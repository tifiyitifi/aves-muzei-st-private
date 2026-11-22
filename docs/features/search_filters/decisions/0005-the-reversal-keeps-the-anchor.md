# The reversal keeps the window's anchor

Status: accepted.

## Context

`CollectionFilter.reverse()` round-trips through `toJsonMap()`/`fromMap`. For a
relative window that re-reads the clock, so `filter.reverse()` produced a filter
anchored later than `filter`. A visible range browses with the positive filter and
excludes with `summaryExclusion`, which is exactly `filter.reverse()`: the
inclusion and the exclusion were computed against two different cutoffs, so an
entry could satisfy neither side and vanish from a filtered view.

## Decision

`RelativeTimeFilter` overrides `reverse()` to rebuild the condition around the
same `cutoffMillis`, flipping only `reversed`.

## Why

- The two sides of a range must partition the library: every entry is either in
  the window or in its complement, at one instant.
- A re-anchoring reversal is still correct for "give me the opposite condition
  from now on", but that is not what a range needs.
- Keeping the cutoff also keeps SQL parity: both fragments describe one window.

## Consequences

- A caller that truly wants a fresh window builds a new filter (or restores it
  from JSON), which re-anchors as before.
- Equality still ignores the anchor, so no key or dedupe behaviour changes.

## Alternatives rejected

- Caching the reversal: it would hide the re-anchor but not fix the JSON path.
- Changing the base `reverse()`: other filters have no anchor, and the JSON
  round-trip is the right default for a value type.
