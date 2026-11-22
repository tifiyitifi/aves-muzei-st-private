# The assist is a value, not a controller

Status: accepted.

## Context

The sheets edit a draft of several fields and the section renders chips for it.
The draft could live in a `ChangeNotifier` controller, in each sheet's state, or in
an immutable value.

## Decision

`SearchAssist` is an immutable value; the search delegate owns one
`ValueNotifier<SearchAssist>` for the page, and each sheet edits a copy and hands
it back (or `null` on dismiss).

## Why

- A sheet is a transaction: either the user confirms the whole draft or nothing
  changes. A mutable shared draft would leak half-edits when a sheet is dismissed.
- Removing one chip is `without(field)`, so a dimension's two filters cannot be
  half-removed.
- Equality arrives for free (`Equatable`), which the section and tests use.

## Consequences

- The assist is not persisted; applying turns it into ordinary filters, which the
  collection and search history keep instead.
- Deleting a chip after applying does not retract the applied filter.
- A new field is a `with*`/`without` pair plus a branch in `toFilters`.

## Alternatives rejected

- A mutable controller shared by the sheets: dismissal would need an undo.
- Persisting the draft: a half-built condition would reappear in the next search.
