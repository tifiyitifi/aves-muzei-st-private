# 0010 — Reading the marker may burn one entry id

Date: 2026-11-24

## Context

`newPhotoMarker()` needs the high-water of the entry id allocator: a photo
imported after setup gets a higher id and is served first by "new then random".
The newest photo by date cannot serve as the marker because ids follow
insertion order, not the displayed date.

`LocalMediaDb.nextId` is a side-effecting getter in both implementations
(`++_lastId` in the sqflite store, `EntryIdAllocator.next()` in the drift store),
so `db.nextId - 1` allocates an id and returns the one before it. The allocated
id is used by nobody: it is read, decremented, and dropped, leaving a permanent
gap in the sequence because allocator ids are never reused.

The re-seed work (`decisions/0009`) added two more call paths for the marker
(`_settleOnce` and `_syncLock`), so the read happens more often than it did
when seeding only covered a fresh state or a new group.

## Decision

The burned id is accepted. No code change: the high-water returned by
`nextId - 1` is still correct (the next real photo gets an id above it), and the
gap has no effect on any query, display or ordering rule. Re-seeding is driven
by user actions — setup, group change, ordering change, an old state — not by
every photo, so the number of burned ids is negligible against the allocator's
100000-id blocks with background top-up.

## Alternatives rejected

- **Add a read-only high-water accessor.** It would touch the shared
  `LocalMediaDb` seam and the drift allocator for a bookkeeping detail that
  changes no observable behaviour.
- **Query `MAX(id)` instead.** It is asynchronous and heavier than a synchronous
  allocator read, and a concurrent connection may already have claimed a higher
  block, which would make the result a worse marker than the current one.

## Consequences

- Each marker read leaves one unused id in the sequence; there is no rule row
  because the choice changes no behaviour the register can falsify.
- The `on StateError` fallback (allocator exhausted before top-up) does not
  allocate an id and stays as it is.
- Recorded under Accepted gaps in `tasks.md` so it is revisited only if marker
  reads ever become per-photo rather than per-action.
