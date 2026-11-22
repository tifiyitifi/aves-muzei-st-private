# Gates are hierarchical prefixes, resolved by longest match

Status: accepted.

## Context

There are four shared channels and a growing set of feature channels, some of
which have sub-areas (`log.db.catalog`, `log.wallpaper.refill`). A flat table
would force a developer to list every child to see a parent's output.

## Decision

A gate on `log.db` applies to every `log.db.*` channel that does not define its
own. When several prefixes match, the longest one wins.

## Why

- Opening one area is one call, the common case at a breakpoint.
- The longest match gives the child the last word without a second resolution
  rule; `log.db` open and `log.db.catalog` closed reads exactly as intended.
- Prefix resolution is O(number of gates), and the table holds a handful of keys.

## Consequences

- A channel name that merely shares a prefix without the dot does not match
  (`log.dbase` is not under `log.db`), which is tested.
- A feature channel is opened by prefix too, so a sub-area can be muted alone.
