# 0006 — Group 0 is the unrestricted sentinel; a group edits on its own page

Date: 2026-11-24

Supersedes: the gallery half of `0005` that kept condition editing on the range
page.

## Context

`0005` unified the gallery scenarios and the wallpaper groups as visibility
groups, but left the gallery page editing the current group's base range,
restrictions and supplements directly, next to the group switcher.

That page still read like the old "base + rules" screen, not like the reference
scenario page: the groups were a button and a toggle, the outside pool replaced
the grid, and there was no place to switch which internal filters are in use.

Group 0 also had to mean 「Unrestricted」 — the state a fresh install browses —
which is incompatible with a row that can hold conditions.

## Decision

- The gallery page lists exactly four things: the **groups**, the **outside
  restrictions**, the **outside supplements**, and the **currently visible**
  result.
- A group is a tile showing its browsed result (its own conditions joined with
  the outside pool). It switches browsing; it is never applied to a media set.
- Group 0 is the 「Unrestricted」 sentinel: empty, first, undeletable, unnumbered
  (data groups are `1..n`), and never a save target.
- A group's base range / restrictions / supplements are edited on
  `VisibleRangeGroupEditorPage`, with the wallpaper page's draft model: edit in
  memory, ask on close, save the whole aggregate.
- The save sheet is called 「save to visible range」 and writes immediately; it is
  not a draft and is distinct from the filter pin.
- The group editor is a bar peer of the wallpaper page: the same side setting,
  both entries ordered by open time, the first opened nearest the range entry.

## Consequences

- The gallery page no longer has an "outside" toggle: the outside sections are
  always visible, so the shared layer cannot be forgotten.
- A group's conditions are invisible until its editor is opened; the tile's
  cover, count and summary carry that information instead.
- The editor's draft can be discarded; the save sheet cannot.
- v20 resets the pre-release gallery scope (the fork has no released installs),
  so no migration has to map a 0-group condition into a new group.

## Alternatives rejected

- **Keep the group's conditions on the main page.** It is the old base+rule
  screen the user rejected, and it cannot express "edit this group" as one
  action.
- **Let group 0 hold conditions and treat it as a normal group.** Then
  「Unrestricted」 would need a second sentinel, and the page would have two
  meanings for the first tile.
- **Keep the editor a pushed page only.** The wallpaper page already
  differentiates in-place and separate entries; the editor is the same kind of
  session and should behave the same way.
