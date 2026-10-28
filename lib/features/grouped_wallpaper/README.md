# Grouped wallpaper

A fork-only feature: wallpaper groups, each owning its own visible range, on top
of the Muzei-style live wallpaper mechanism.

## Status

- **Done**: group model, layout invariants, bundled defaults (JSON), storage
  (`wallpaper_groups` table, schema v7; `baseActive` in v9), controller with the
  page's in-memory draft, the wallpaper-group page reachable from the
  visible-range page's More menu / the shared bottom-bar entry, and the engine's
  first closed loop (Dart baking + native single-image service).
- **Not done yet**: auto-advance, the notification, and the availability label.
  Until then a sync only happens when the service starts or the user asks for it,
  and the engine has no timer of its own.

## The engine

`lib/features/grouped_wallpaper/engine/` is the control plane; the native service
only draws. One sync:

1. reads the *saved* current group and its range (`SavedGroupedWallpaperPlanLoader`,
   deliberately bypassing the page's draft);
2. resolves the media set with `wallpaperMediaSetFilter`, skipping the image
   already on screen and any file that disappeared since the last scan;
3. bakes one cover-cropped PNG at `WallpaperManager.desiredMinimumWidth`;
4. writes `state.json` and `current.png` atomically, then asks the renderer to
   reload.

`state.json` is Dart-owned and read-only for the native side, and it carries what
the notification will need (group number, resolved group name, entry, count,
lock). Every outcome is recorded instead of thrown: an empty group, a locked
range, a missing photo or a failed bake all end in the grey placeholder, except a
locked range, which keeps the frame it froze on.

The service asks the app for a frame when it starts and when the app attaches, so
the wallpaper gets its first photo without a background worker; if the app is not
running, the renderer keeps showing its placeholder until the app is opened. The
engine is attached at startup (`main_common`) for that reason, and the page
re-probes `isActive` when it opens or resumes.

The native side lives in
`android/app/src/main/kotlin/deckers/thibault/aves/features/grouped_wallpaper/`
and uses its own state root (`filesDir/grouped_wallpaper`), so it shares no files
with Muzei. It never touches the database.

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
`pictures` → `dcim` → `all`, so group 1 is the Pictures path, group 2 DCIM and
group 3 the unrestricted one, which is also the current group on a fresh
install. Names are ARB keys (`@wallpaperGroupDefault*`) and follow the app
language; once the user renames a group the stored name is plain text and no
seeding pass overwrites it.

**Failure is closed.** A group is a privacy tool, so when a bundled `standard`
path cannot be resolved the group's base range becomes a deny-all filter
(`SetOrFilter({})`, which matches nothing and compiles to `0 = 1`) instead of
falling back to "everything". The same principle is stated in the About page and
in the visible-range preset parser, which simply does not offer a candidate whose
path is unknown.

A group owns its range only. It never shows the gallery's preset catalogue or
its default restriction/supplement candidates: those belong to the visible-range
page. Conditions are added by pinning them from a media set, and the group page
only shows, toggles, renames, takes out and deletes what is already there. Older
builds materialized that catalogue into every group; it is pruned on every start
(not only on a defaults bump), so a restored backup cannot bring it back.

Each group range starts with the 「All images」 tile, the wallpaper counterpart of
the gallery page's 「Unrestricted」. It is not a condition: its image filter set is
what gives it the images' cover and count (the same count the group cards show),
and tapping it switches the group's base off without deleting anything. A base
keeps its filters when switched off (`baseActive`), so it can be switched back
on. Rules are a separate section and keep their own switches. An empty rules
section keeps one 「None」 slot so the page still shows the section exists.

## The page's draft

The wallpaper page is a draft until the user saves it. The first time it opens in
a process it loads every group and range into memory (the wallpaper feature may
never be visited); from then on group edits — including pin targets, since they
read the same aggregate — stay in memory. The database and the live wallpaper
keep the saved state.

- **Save changes** writes groups, ranges, rules and deletions in one transaction.
- **Discard changes** reloads the saved state.
- **Set as wallpaper** opens the system live-wallpaper chooser for the grouped
  service; it is disabled when the platform channel is unavailable.
- **Sync wallpaper now** saves a pending draft and asks the engine to apply it
  immediately instead of waiting for the wallpaper's interval. The entry is
  disabled while the grouped wallpaper is not the system wallpaper, and the
  status row under it reports what the renderer is showing.

Group cards take part in multi-selection in all three switcher styles: a tap
toggles them while the page is selecting, and a long press starts a selection
with that group. Group 0 is never selectable. Deleting the selected groups keeps
at least one group and stays a draft until it is saved; deleting the viewed group
moves the page to the first remaining one.

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
