# `null` filters mean "use the default", `{}` means "all media"

Status: accepted.

## Context

The collection can be opened with an explicit filter set (from a chip, a
notification, a navigation item) or with the configured home collection. The
snapshot has to distinguish "the user had all media" from "this page has no
filter set of its own".

## Decision

The plan returns `null` filters when the recorded page is not the collection, and
the recorded set — including an empty one — when it is. The home page resolves
`null` to the configured default.

## Why

- An empty set is a real browsing state ("all media"), so collapsing it into
  `null` would reopen the home collection instead.
- A non-collection page has no filter set at all, and an empty set there would
  wrongly mean "all media" when the page rebuilds from its own settings.

## Consequences

- `planSessionRestore` must not normalise `{}` to `null`.
- The recorded base follows the same rule only when it is the collection.

## Alternatives rejected

- Always returning a set: the home page would lose the configured default.
- Always returning `null` for an empty set: "all media" would become "home
  collection".
