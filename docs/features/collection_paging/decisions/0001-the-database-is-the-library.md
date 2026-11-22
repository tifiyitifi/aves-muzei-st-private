# 0001 — The database is the library

Status: accepted.

## Context

The upstream source materializes every entry in memory. On a library of hundreds
of thousands of rows that is both slow and fatal: the app loads everything before
the first frame and keeps it all. Browsing, counts, album lists and the viewer
all read the same in-memory list.

## Decision

A paged view uses an entry-free `CollectionSource`. The database is the library:
windows are read on demand, summaries and stats are queried, selection feeds walk
the scope in bounded batches. Two seams keep callers honest:

- the source reports whether a summary provider is attached, which is the
  authoritative "reads the database" signal;
- `PagedScopeGuard` stops an action that would read the empty in-memory source.

## Consequences

- Memory is bounded by the window cache, not by the library.
- Every capability that used to read `source.visibleEntries` needs a database
  path: summaries, stats, selection, targets, viewer copies.
- A fully loaded source is left alone, because switching it to the database
  behind a legacy view would make counts disagree with the visible rows.
- A page that forgets to attach the provider shows an empty album list; that is
  the recurring failure this decision makes visible.
