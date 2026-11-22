# 0001 — A range is a filter expression

Status: accepted.

## Context

The feature replaced an older scenario mechanism that stored a list of selected
entries. A list has two problems on a large library: it must be materialized to
be enforced, and it cannot be expressed to the database. Every surface (grid,
summary counts, legacy scan) would have to apply it in memory, and the three
would eventually disagree.

## Decision

A range stores a base filter set, restriction rules (AND), supplement rules (OR)
and an evaluation order. `resolve()` builds one `CollectionFilter` tree, and the
three browsing paths ask one gate for it. Summary queries use the tree's
complement, so they describe the same set as "entries to exclude".

## Consequences

- No entry list is materialized; the range works at any library size.
- The page can show a cumulative count by resolving the same expression one step
  earlier (`resolvedIntermediate`).
- Two evaluation orders exist because the old chips had them; a third would be a
  new expression shape, not a new setting.
- A range is only as expressive as the filter tree. Conditions the filter model
  cannot express cannot be a range.
