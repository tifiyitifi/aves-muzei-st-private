# 0009 — A new-photo marker carries its seeded flag

Date: 2026-11-24

## Context

The seeding fix made "new" mean added after the group started playing, but it
only seeded when there was no state, a new group, or a zero marker. A state that
had already played kept its last-shown photo id, and ordering edits do not bump
`updatedAt` or re-bake the frame, so switching to "new then random" left that
same stale marker. Both cases made the ordering walk the whole library in id
order before it ever picked at random.

Ordinary state versions cannot distinguish a stale marker from a seeded
high-water: after new photos arrive, a seeded marker is also below the current
high-water. Re-seeding on every restart would swallow photos still queued for
the group.

## Decision

Each marker holder persists a `markerSeeded` flag next to `newestEntryId`. The
engine re-seeds once when the flag is false, the marker is zero, the group or
range changed, or the ordering changed; a seeded marker survives same-group
restarts. Both surfaces re-seed on an ordering edit, using the ordering signal
captured before the home run writes the new value. The flag joins the state JSON
without a version bump, like the other fields added after v7: an absent flag
reads as unseeded.

## Alternatives rejected

- **Re-seed on every start.** A new photo queued after setup has an id above the
  old high-water but below the new one, so a fresh seed would silently drop it.
- **Compare the marker with the current high-water.** The comparison cannot tell
  a stale marker from a seeded one once new photos have arrived.
- **Bump the state version for the migration.** `needsUpgrade` only rewrites the
  file for older versions; it would lose the distinction on v6/v7 states and
  would re-bake a frame the user did not ask to change.

## Consequences

- `GroupedWallpaperState` and `GroupedWallpaperLockFrame` carry `markerSeeded`
  through `copyWith` and the JSON contract; an old file reads as unseeded.
- The engine re-seeds in `_startOver`, in `_settleOnce` before `_pickNext`, and
  in `_syncLock` before the decoy's pick.
- `rules.md` `ORD-6` through `ORD-9` and `spec.md` FR-14 hold the behaviour.
