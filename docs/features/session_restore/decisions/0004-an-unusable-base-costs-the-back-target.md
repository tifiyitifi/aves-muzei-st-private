# An unusable base costs the back target, not the page

Status: accepted.

## Context

A snapshot can name a base page that this build cannot reopen (a removed route),
that is the page itself, or that was saved under a page which is not pushed. The
whole record could be rejected, or the base could be repaired.

## Decision

The reader drops an unusable base (and its filters) and keeps the top page, which
stays valid. A snapshot whose top page is unusable is rejected entirely. The
writer applies the same predicate, so an invalid record is never saved.

## Why

- The top page is what the user was looking at; losing the back target is a
  smaller loss than losing the page.
- Repairing is the only outcome that needs no error message on a cold start.
- Sharing `isValid` between reader and writer means persistence cannot create a
  record the reader would reject.

## Consequences

- Two code paths answer differently for the same malformed object: parsing
  repairs it, while a constructed object is reported invalid. Both are tested.
- The base's filters are only useful while the base survives, so they are
  dropped with it.

## Alternatives rejected

- Rejecting the whole snapshot on an unusable base: the user would lose the page
  they were on because of a stale back target.
- Falling back to the configured home page as the base: that invents a page the
  user did not have under them, unless no base was recorded at all (the plan's
  stand-in).
