# Grouped wallpaper

A fork-only feature: wallpaper groups, each owning its own visible range, on top
of the Muzei-style live wallpaper mechanism.

## Status

- **Done**: group model, layout invariants, bundled defaults (JSON), storage
  (`wallpaper_groups` table, schema v7; `baseActive` in v9), controller with the
  page's in-memory draft, the wallpaper-group page reachable from the
  visible-range page's More menu / the shared bottom-bar entry, the engine's
  closed loop (Dart baking + native slot queue), global gestures, and the
  immersive view page.
- **Not done yet**: auto-advance intervals, per-group effects, the notification,
  and the availability label. Until then a sync happens when the service starts,
  on a wallpaper tap, or when the user asks for it.

## The engine

`lib/features/grouped_wallpaper/engine/` is the control plane; the native service
only draws. Two entry points share one pipeline:

- `prepare()` keeps the queue ready for the saved group and **never requires the
  service to be the system wallpaper yet**, because the system picker can take a
  moment to hand it over; and
- `syncNow()` is the user asking for the next photo, and only applies while the
  service really is the system wallpaper.

One run:

1. reads the *saved* current group, its range, the off switch and the ordering
   (`SavedGroupedWallpaperPlanStore`, deliberately bypassing the page's draft);
2. adopts the first enabled group when activation finds no group selected;
3. adopts a slot the renderer promoted (over the channel when the app is
   running, from `runtime.json` in a background run);
4. resolves the media set with `wallpaperMediaSetFilter` and picks each missing
   slot through the saved ordering;
5. bakes a cover-cropped PNG at `WallpaperManager.desiredMinimumWidth` per slot;
6. writes `state.json` and the slot photos atomically, then asks the renderer to
   reload.

A plain `prepare` skips the bake when the state already holds the full queue for
the saved group and is newer than the group's and the range's `updatedAt`, so an
app start on an untouched install costs a database read and a file stat, not a
bake.

### The promotion queue

`state.json` carries `current → next → next2`, so the renderer can move to the
next photo on a double tap without waiting for Flutter: it switches to the
texture it already uploaded, records the promotion in `runtime.json`, and asks
the app (or the shared background worker) to bake the freed slot. A tap that
arrives before the slot is uploaded is buffered (capacity 5, 10 s expiry) and
replayed as prefetched slots land, so a burst of taps keeps advancing instead of
stopping after two.

### Ordering

The next photo is chosen the way Muzei chooses its artwork, and the default is
the same:

- `newThenRandom` (default): photos added after the wallpaper was set up are
  served in id order, then the group falls back to random;
- `inOrder`: walk the group newest first and wrap around at the end;
- `random`: pick a random photo, avoiding the one on screen and the recently
  shown ones (bounded to 32).

Each ordering is a database query, not a walk of a fixed window: the old
"newest 32" window could never leave those 32 photos, which made a tap cycle
through a handful. `newestEntryId`, `cursor` and `recent` live in `state.json`
(v3), so an app restart continues the walk instead of starting over.

`state.json` is Dart-owned and read-only for the native side, and it carries what
the notification will need (group number, resolved group name, entry, count,
status). Every outcome is recorded instead of thrown: an empty group, a locked
range, a missing photo or a failed bake all end in the grey placeholder, except a
locked range or a turned-off feature, which keep the frame they stopped on. A
failed *prefetch* keeps the frame and the queue; only a group with no usable
photo at all falls back to the placeholder.

The service asks the app for a frame when it starts and when the app attaches, so
the wallpaper gets its first photo without a background worker; if the app is not
running, the renderer keeps its placeholder until the app is opened. The engine
is attached at startup (`main_common`), and the page re-probes `isActive` when it
opens or resumes.

## Turning it on and off

`groupedDisabled` (AppMeta, `wallpaper.groupedDisabled`) is the explicit off
switch, and it is deliberately separate from the `current` flag: turning the
feature off keeps the group that was playing, so turning it back on returns to the
same content, and the flag survives a reboot, where the service starting again
would otherwise look like a fresh activation.

- **Set this group as wallpaper** (a real group) makes it current, turns the
  feature on and prepares the frame. The system chooser is only opened the first
  time, when the grouped service is not the system wallpaper yet.
- **Turn off grouped wallpaper** (group 0) sets the flag and freezes: the last
  frame stays and nothing follows the group. Disabling never changes the wallpaper
  the system is already showing.
- **Deleting or disabling the group that was playing** freezes and turns the
  feature off; it never switches to another group.
- **Activation with no group current** (the service starting while nothing is
  selected and the feature was not turned off) adopts the first enabled group, so
  turning the wallpaper on never leaves the placeholder.

The page shows one state icon per card: play on the group that is really playing,
and stop on group 0 whenever the grouped wallpaper is not playing (not the system
wallpaper, or turned off). A lamp marks the group whose range the page shows.

The native side lives in
`android/app/src/main/kotlin/deckers/thibault/aves/features/grouped_wallpaper/`
and uses its own state root (`filesDir/grouped_wallpaper`), so it shares no files
with Muzei. It never touches the database.

The headless path is shared with Muzei instead: `features/live_wallpaper_refill/`
owns the `vm:entry-point` isolate, the warm engine and the WorkManager chain, and
dispatches by target (`muzei` / `grouped`) to
`entry/background_refill.dart`. The grouped run attaches the engine and either
prepares a frame or advances, so a tap or an interval still applies when no page
is mounted. Files, renderers and intervals stay per wallpaper.

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

- **Save changes** writes groups, ranges, rules and deletions in one transaction,
  then re-bakes so the frame on screen matches what was saved.
- **Discard changes** reloads the saved state.
- **Set this group as wallpaper / Turn off grouped wallpaper** is one entry that
  follows the viewed group (see *Turning it on and off*).
- **Sync wallpaper now** saves a pending draft and asks the engine to apply it
  immediately instead of waiting for the wallpaper's interval. The entry is
  disabled while the grouped wallpaper is not the system wallpaper or is turned
  off, and the status row under it reports what the renderer is showing.

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
