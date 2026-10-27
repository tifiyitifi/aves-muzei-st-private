# Grouped wallpaper

A fork-only feature: wallpaper groups, each owning its own visible range, on top
of the Muzei-style live wallpaper mechanism.

## Status

- **Done**: group model, layout invariants, bundled defaults (JSON), storage
  (`wallpaper_groups` table, schema v7; `baseActive` in v9), controller with the
  page's in-memory draft, and the wallpaper-group page reachable from the
  visible-range page's More menu / the shared bottom-bar entry.
- **Not done yet**: the live wallpaper engine (baking, notifications, `isActive`
  arbitration), the availability label. Until then a group only decides which
  filters it *would* use and 「Sync wallpaper now」 stays disabled.

## Concepts

- **Group 0** (`WallpaperGroup.none`, `wallpaperGroupNoneId = 'none'`) is a
  constant, not a row: it owns no range, never changes the wallpaper and never
  joins the notification rotation. "No group is current" *is* group 0.
- **Groups 1..n** are rows. `position` is the only stored ordering fact; the
  displayed `number` is derived from it, so numbers are always contiguous.
- **Segments**: enabled groups come first (`1..m`), disabled ones after
  (`m+1..n`). Dragging moves a group inside its own segment only; the enable
  switch is what crosses the boundary, and it moves the group to the end of the
  enabled segment (or the start of the disabled one).
- **Current**: at most one group carries `current`. Disabling or deleting the
  current group clears the flag, i.e. falls back to group 0.
- **Range ownership**: each group owns exactly one `wallpaper`-scope visible
  range, whose id is *derived* (`wallpaperGroupRangeId`), never stored. Deleting
  a group deletes its range, rules and applied targets in the same transaction.

## Defaults

`assets/wallpaper_groups.json` declares the bundled groups, in display order:
`all` → `dcim` → `pictures`. Names are ARB keys (`@wallpaperGroupDefault*`) and
follow the app language; once the user renames a group the stored name is plain
text and no seeding pass overwrites it.

**Failure is closed.** A group is a privacy tool, so when a bundled `standard`
path cannot be resolved the group's base range becomes a deny-all filter
(`SetOrFilter({})`, which matches nothing and compiles to `0 = 1`) instead of
falling back to "everything". The same principle is stated in the About page and
in the visible-range preset parser, which simply does not offer a candidate whose
path is unknown.

A group owns its range only. It never shows the gallery's preset catalogue or
its default restriction/supplement candidates: those belong to the visible-range
page. Conditions are added by pinning them from a media set, and the group page
only shows, toggles, renames, takes out and deletes what is already there.

Each group range starts with the 「no filters」 control as its first tile. It is
not a condition: tapping it switches the group's base and every rule off without
deleting anything. A base keeps its filters when switched off (`baseActive`), so
it can be switched back on. An empty rules section keeps one 「None」 slot so the
page still shows the section exists.

## The page's draft

The wallpaper page is a draft until the user saves it. The first time it opens in
a process it loads every group and range into memory (the wallpaper feature may
never be visited); from then on group edits — including pin targets, since they
read the same aggregate — stay in memory. The database and the live wallpaper
keep the saved state.

- **Save changes** writes groups, ranges, rules and deletions in one transaction.
- **Discard changes** reloads the saved state.
- **Sync wallpaper now** saves a pending draft and asks the engine to apply it
  immediately instead of waiting for the wallpaper's interval. The entry is
  disabled until a grouped-wallpaper engine has attached to `wallpaperEngineLink`.

## Browsing scopes

The gallery range and a group range are independent data sets. While the
wallpaper page is open, `VisibleRangeGate.overlay` adds the selected group's
range to browsing (gallery AND group), and the page can temporarily ignore the
gallery range when it is unlocked. Leaving the page clears the overlay, so every
other surface acts as group 0. The live wallpaper never reads the gate: it uses
the saved group range through `wallpaperMediaSetFilter`.

## Media set

`wallpaperMediaSetFilter` is the only way to turn a group into filters: every
image (`MimeFilter(MimeTypes.anyImage)`) that the group's range keeps. The engine
must call it instead of composing filters itself, so "images only" and
fail-closed stay in one place.

## Relation to `muzei_wallpaper`

`muzei_wallpaper` is the existing Muzei client: a single artwork source with its
own state and settings. This feature is a *second* live wallpaper that rotates
whole groups; the two are independent and mutually exclusive at the system level
(only one live wallpaper can be active). They share the technical mechanism, not
their data.
