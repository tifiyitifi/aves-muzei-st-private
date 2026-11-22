# A missing value never matches a range; its reversal does

Status: accepted.

## Context

Some entries have no taken date, and some have no content id. A bounded condition
has to decide what "no value" means, in Dart and in SQL.

## Decision

The positive test rejects an entry with no value for the field. The reversed test
accepts it. SQL mirrors this with `COALESCE((fragment), 0) = 0` for a reversal.

## Why

- "Taken before 2020" is a statement about a date; an entry without one does not
  satisfy it.
- The reversal is the complement, and the complement of "has a date before 2020"
  includes "has no date". Keeping the two sides complementary is what makes the
  filter usable as an exclusion in a visible range.
- A NULL-unsafe negation would drop those rows from both sides, making a row
  disappear from the library whenever a range was active.

## Consequences

- The assistant's date presets never show undated entries.
- A reversed range is a reliable way to find rows missing a field.
- The SQL fragment cannot be written as a plain `NOT (...)`; it must coalesce.

## Alternatives rejected

- Treating "no value" as zero: a `0` date means unknown, not 1970.
- Rejecting it on both sides: the row would vanish from every filtered view.
