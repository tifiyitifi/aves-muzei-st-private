# One numeric range type for date, size, dimensions and content id

Status: accepted.

## Context

The assist offers five bounded conditions with the same shape: a field, an
optional lower bound, an optional upper bound, and a reversal.

## Decision

Implement one `RangeAssistFilter` with an `AssistRangeField` enum instead of five
filter classes.

## Why

- The bound logic, JSON shape and reversal are identical; five classes would
  duplicate them five times.
- One SQL dispatch site keeps the NULL handling in one place.
- Adding a field is an enum value plus a predicate, not a new filter type in
  upstream's factory.

## Consequences

- The field name is persisted, so a renamed value needs a migration or must be
  dropped gracefully (unknown fields drop the filter).
- A field's value semantics (best date, displayed size) live in one switch, which
  is also where a new field is reviewed.

## Alternatives rejected

- Five classes: duplicated equality, JSON and SQL.
- A generic `min/max` filter without a field: the SQL seam could not choose a
  column.
