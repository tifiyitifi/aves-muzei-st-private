# 0002 — The wallpaper scope joins the gallery range

Status: accepted.

## Context

The wallpaper page browses the media a group will use, while the gallery keeps
its own visible range. Both are real restrictions and both belong to the same
library. Replacing the gallery range with the group range would lose the user's
browsing context on the way back; ignoring the group would browse media the
wallpaper will never show.

## Decision

The wallpaper page publishes an in-memory overlay: its group filter, plus an
optional `gallerySuspended` flag. The browsing gate intersects the two ranges,
and the live wallpaper ignores the gate entirely — it resolves its saved group
range directly.

The overlay is owned by a per-page token. A newer page takes over, and an older
page's release is a no-op, even when the two pages published an equal value.
Releasing is deferred to a microtask because it can run during a route
transition.

## Consequences

- Leaving the wallpaper page restores the gallery range without a write.
- Suspending the gallery range is a view choice, not a persisted setting.
- Group 0 clears the overlay instead of publishing an empty one.
- A process restart returns to the gallery range alone.
- Value equality is used for cache invalidation, identity for ownership; the two
  are deliberately separate.
