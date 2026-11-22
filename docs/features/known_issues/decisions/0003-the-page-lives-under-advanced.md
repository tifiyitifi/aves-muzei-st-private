# The page lives under Advanced, next to the settings that accept the trade-off

Status: accepted.

## Context

The known issues describe what the paged engine and the batch engine cannot do.
The user meets them in two moments: reading About, and changing the collection
engine or the batch expectations under Advanced.

## Decision

Keep the About section (which is where the list started) and add a page under
Advanced that renders the same body. The page is reached from the settings
catalog (`MetaPageKeys.knownIssues`), not from a drawer or an app-bar action.

## Why

- The question "what did I give up by switching the engine?" is asked in
  Advanced, next to the selector.
- A second reader costs one registry entry because both use the shared body.
- About remains the place a new user discovers the list.

## Consequences

- The page must stay in the settings catalog's coverage gate; removing the entry
  makes the page unreachable while the file still compiles.
- The list may not mention a view that is about to become supported: the page is
  read as current behaviour, not as a plan.

## Alternatives rejected

- A standalone route in the drawer: the list is a reference, not a destination.
- Duplicating the entries in the settings page: the two would drift.
