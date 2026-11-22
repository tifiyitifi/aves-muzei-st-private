# An allow-list of routes, never a serialized navigator stack

Status: accepted.

## Context

Restoring "where the user was" can be read as "rebuild the whole back stack".
Most pages in the app take constructor arguments (a filter, an entry, a
directory) that a route name cannot reproduce.

## Decision

`restorableSessionRoutes` names the pages that may be reopened from a name
alone; `pushedRestorableSessionRoutes` names the subset that has a meaningful page
below it and therefore records a base.

## Why

- A page that needs an argument cannot be rebuilt from a name, and guessing the
  argument would reopen a different page.
- One allow-list is the single place that decides what is safe; adding a page is
  one reviewable edit.
- Transient sub-pages stay off the list, so a sources or gestures page never
  becomes the destination.

## Consequences

- The viewer, the explorer, settings sub-pages and pickers are not restored;
  the media set under a viewer is, because the collection is on the list.
- A new top-level page must be added to the list deliberately, or it is never
  remembered.

## Alternatives rejected

- Serializing the navigator stack: most routes cannot be rebuilt.
- Restoring the last route name whatever it is: the launch would show a page with
  missing arguments.
