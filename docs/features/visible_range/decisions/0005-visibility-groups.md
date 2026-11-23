# 0005 — A range is a visibility group, not a base plus rules

Date: 2026-11-23

## Context

The gallery used one range with a single mutually exclusive **base** and shared
restriction/supplement rules. The wallpaper page reused the same shape for each
group, but needed the opposite source semantics: several sources in parallel,
each marked for Home, Lock or both.

The same user need drives both: keep a library of filter sets, activate one or
several, and keep the rest editable. The difference is only the selection policy
(one or many) and the surface axis.

## Decision

A range is one **visibility group**:

- the gallery owns N mutually exclusive groups plus one scope-wide outside pool;
- a wallpaper group owns exactly one group and marks each condition per surface;
- inside a group a condition is a `source` (OR), a `restriction` (AND) or a
  `supplement` (OR);
- the old base becomes the group's `source` condition; the old shared rules move
  to the outside pool;
- a pin splits the media set by attribute (albums/paths to sources, the rest to
  restrictions) so the result stays equivalent, and the user can override the
  role;
- the lock freezes the whole scope, not one row: a locked gallery cannot switch
  groups or edit the outside pool, and a locked wallpaper group set hides the
  other groups and refuses edits to every group.

## Consequences

- `resolve()` has one formula and the single/multi selection difference is a
  guard on the enable toggle, not a second model.
- The gallery lock is a feature-wide freeze; there is no per-group lock.
- Defaults become built-in **groups**; they are re-added when missing but never
  pruned, because deleting a user-edited group is worse than keeping a stale
  default.
- v19 migrates the base into a `source` rule and keeps the legacy base columns
  one release so a rollback can still read the old shape.

## Alternatives rejected

- Two parallel models (exclusive base for the gallery, source list for wallpaper):
  duplicates the store, the page and every test.
- Per-group locks: switching away from a locked group would grant permissions.
- Pruning built-in groups on a defaults bump: silently deletes user edits.

## Superseded by

[`0006-group-zero-and-the-group-editor.md`](0006-group-zero-and-the-group-editor.md)
(partially): the gallery page now lists only the groups and the outside pool,
a group's own conditions edit on their own draft page, and group 0 is the
「Unrestricted」 sentinel rather than a container.
