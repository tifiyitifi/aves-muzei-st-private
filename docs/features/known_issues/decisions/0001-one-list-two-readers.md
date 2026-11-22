# One list for the About section and the settings page

Status: accepted.

## Context

The limitations of the paged engine and the wallpaper family were described in
the About page. The same trade-offs are decided in Advanced, next to the engine
selector, so the user asks the question there.

## Decision

Both readers call `knownIssues(context)` (and the section's `buildBody`); no
reader keeps its own copy of the entries.

## Why

- One edit adds or removes an entry everywhere.
- The two readers cannot disagree about what the app currently accepts.
- The order and numbering are shared, so a number a user quotes means one entry.

## Consequences

- The About page can only add chrome, not content, which is why the fork adds one
  section there rather than editing upstream's page body.
- A reader with a different list (for example "first-run warnings") must filter
  the shared list, not fork it.

## Alternatives rejected

- Two lists kept in sync by hand: the first divergence is invisible until a user
  quotes an entry that no longer exists.
- A settings-only page: the limitations are about the app, so they belong on
  About too.
