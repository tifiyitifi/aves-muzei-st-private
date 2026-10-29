# Grouped wallpaper

A fork-only feature: wallpaper groups, each owning its own visible range, on top
of the Muzei-style live wallpaper mechanism.

## Status

- **Done**: group model, layout invariants, bundled defaults (JSON), storage
  (`wallpaper_groups` table, schema v7; `baseActive` in v9; per-group `effects`
  in v10; per-group `interval`/`ordering` in v11), controller with the page's
  in-memory draft, the wallpaper-group page reachable from the visible-range
  page's More menu / the shared bottom-bar entry, the engine's closed loop (Dart
  baking + native slot queue), global gestures, the immersive view page, per-group
  home/lock effects with a copy-to-other-groups grid, per-group auto-advance
  (interval + ordering, scheduled through the shared WorkManager chain), the
  four-layout notification with photo, group and freeze actions, and the
  availability label under the group switcher.
- **Not done yet**: the notification's copy/usage-history buttons (shown but
  disabled), filtering the management surfaces (settings, explorer, vaults,
  recycle bin) while a range is locked, temporary/permanent selection ranges,
  Aves Copy, and import/export.

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
3. adopts a slot the renderer promoted, from `runtime.json` (the renderer writes
   it synchronously, so a running app and a background run read the same
   record);
4. resolves the media set with `wallpaperMediaSetFilter` and picks each missing
   slot through the saved ordering;
5. bakes a cover-cropped PNG at `WallpaperManager.desiredMinimumWidth` per slot,
   plus one effect PNG per surface when the group's effects are not identity;
6. writes `state.json` and the slot photos atomically, then asks the renderer to
   reload.

A plain `prepare` skips the bake when the state already holds the full queue for
the saved group and is newer than the group's and the range's `updatedAt`, so an
app start on an untouched install costs a database read and a file stat, not a
bake.

### The promotion queue

`state.json` carries `current → next → next2`, so the renderer can move to the
next photo on a double tap without waiting for Flutter: it switches to the
texture it already uploaded, writes the promotion to `runtime.json`
synchronously, and asks the app (or the shared background worker) to bake the
freed slot. A tap that arrives before the slot is uploaded is buffered (capacity
5, 10 s expiry) and replayed as prefetched slots land, so a burst of taps keeps
advancing instead of stopping after two.

A promotion is forward-only on both sides. Dart adopts a runtime only when it
points at a slot queued after the current one, and re-reads it just before
writing `state.json` so a tap that landed during a bake is not rewound. The
renderer does the same on reload: if the new state's queue still contains the
slot on screen after its current, it keeps that slot, shifts the queue to it and
rewrites the runtime with the new generation. Without that, a tap could show the
next photo and then snap back to the one it just left.

### Effects

Effects belong to the group, with separate home and lock values and Muzei's
optional link toggle. They are stored as one JSON column on the group row
(`effects`, schema v10), so an upgraded group reads the identity configuration
and keeps its photos sharp.

The baker applies the same math as Muzei (blur at a quarter of the surface
height then upscale, greyscale matrix, dim from the artwork's own darkness) and
writes `slots/<id>/home.png` / `slots/<id>/lock.png` next to the sharp
`photo.png`. An identity effect points at the sharp file instead of writing a
second copy. The native renderer picks the file for the surface being drawn,
using the keyguard state, so only one texture per slot is uploaded.

The effects page is bound to the viewed group and applies as the sliders move,
bypassing the range draft: effects are display preferences, and the live
wallpaper should follow them without a separate "save". Its copy action opens a
group grid with the app-wide XOR-range gesture and writes the same configuration
to every selected group in one transaction.

### The notification

`GroupedWallpaperNotification` (Kotlin) posts an ongoing notification while the
grouped service is the system wallpaper, styled after Aves-ST's foreground
wallpaper bar: a coloured group-number badge, the group name and the photo title,
plus borderless actions. The button set follows the keyguard, and the expanded
layout's first button switches between the two sets:

| | Collapsed (4) | Expanded (5) |
|---|---|---|
| Photo actions (unlocked default) | previous / next photo / copy\* / record\* | switch / previous / next / copy\* / record\* |
| Group actions (locked default) | previous / next group / freeze / next photo | switch / previous / next group / freeze / next photo |

`*` copy and usage history keep Aves-ST's icons but are disabled (dimmed, no
action) until those features exist. The channel is `grouped_wallpaper_v2`,
`IMPORTANCE_HIGH`, no badge, silent and vibration-free **at the channel level**:
silencing the notification itself put the bar in the system's "silent" group,
which MIUI hides on the lock screen. The notification is also
`VISIBILITY_PUBLIC`, so the group and photo names stay readable on the lock
screen, is ongoing and only alerts once, so a reload never buzzes.

While a real (non-preview) engine is attached, the service promotes the bar to
its own foreground-service notification (`specialUse`, Android 14+), because MIUI
also hides a silent *non-foreground* notification on the lock screen. Promoting
the already-running wallpaper service is the only form Android 12+ allows:
starting a second foreground service from the background is rejected. The
notification is otherwise posted normally, and dropping the foreground state
(`stopForeground`) is what removes it; turning the grouped wallpaper off does
that before cancelling.

Tapping the body opens the wallpaper group page (`/wallpaper_groups`), which the
app accepts as a shortcut route; the expanded first button only switches the
button set. The screen broadcasts (`ACTION_SCREEN_OFF`, `ACTION_SCREEN_ON`,
`ACTION_USER_PRESENT`) switch the layout family and the home/lock effect image
together, and return the button set to the keyguard's default.

Actions are broadcasts to `GroupedWallpaperActionReceiver`, so they work without
an Activity. "Next photo" first promotes the prefetched slot in the live renderer
(instant, like a double tap); every other action goes to the mounted app when its
engine listens and to the headless worker when it does not. The commands are the
names of `GroupedWallpaperCommand` (`previousArtwork`, `nextGroup`, ...), so both
sides share one vocabulary. Turning the grouped wallpaper off cancels the
notification.

"Previous photo" re-bakes the remembered entry instead of restoring its old file
(slots are recycled), and re-checks it against the group's media set: locking a
vault or hiding a filter between two photos can never bring the hidden photo
back. A v3 state's history has no group id, so its entries are treated as
belonging to the current group.

### Freezing

`groupedPaused` (AppMeta, `wallpaper.groupedPaused`) freezes the wallpaper on the
current photo. It is separate from the group's visible-range lock and from the
off switch: the frame stays, but the renderer refuses to promote on a tap and the
notification shows the closed lock. The notification's freeze button toggles it;
an explicit "next photo" resumes it, and switching group also resumes. The flag
travels in `state.json` (`paused`, v4), so the native renderer knows about it
without asking Flutter.

### The view page

A three-finger tap opens an immersive view of the current photo, modelled on
Muzei's artwork screen: pan and zoom, chrome visible on open and toggled by a
tap, the group · count · title at the bottom left and the menu at the bottom
right. The menu has 「Open wallpaper groups」, 「Open in gallery」 and share. A
wallpaper gesture has no Activity, so the view is pushed over the playing
group's page, itself over the app's home page: back walks view → group page →
home instead of closing the app, and the group page starts on the group being
played. Opened from the group page, 「Open wallpaper groups」 pops back to it.

### Ordering

The next photo is chosen the way Muzei chooses its artwork, and the default is
the same. The ordering **belongs to the group** (`wallpaper_groups.ordering`,
persisted by enum name; schema v11 migrated the old global value into every
group):

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

### Auto-advance

Each group also owns its interval (`wallpaper_groups.interval`, seconds; `0` is
off, the default). The values are Muzei's (`15 min` … `3 days`), edited from the
group page's More → 「Auto-advance」, which writes immediately like effects and
does not bump `updatedAt`: the contract only affects future picks, so the frame
on screen is never re-baked just because the interval changed.

Scheduling reuses the shared native WorkManager chain
(`LiveWallpaperRefillScheduler`, per target) through the grouped channel's
`scheduleAutoAdvance`; a finished interval run reschedules itself. The engine
applies the interval on every non-advance run, on freeze/resume and when the page
edits it, and schedules **nothing** while the wallpaper is frozen, turned off or
on group 0, so a frozen wallpaper does not wake up for a frame it would refuse to
show. A frozen wallpaper also ignores an interval run (`refill(advance: true)`
does not promote), while an explicit "next photo" resumes it.

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

The gallery range and a group range are independent data sets. The group page
publishes the range of the group it shows through `VisibleRangeGate`, so browsing
— the page itself and every other tab — sees the gallery range **and** the group
range, exactly the photos the wallpaper may use. The page can temporarily ignore
the gallery range while it is open; that choice is page-local and is restored on
leaving.

Leaving the page keeps the group scope: the restriction follows the viewed group
until the user selects group 0, which clears it. It is in-memory only, so a
process restart returns to the gallery range alone. The live wallpaper never reads
the gate: it uses the saved group range through `wallpaperMediaSetFilter`, so
gallery browsing can never narrow the wallpaper result.

All three browsing paths ask the same gate — the paged predicate, the summary
query and the legacy in-memory scan — so the album list, the album counts and a
media set opened from either path agree. The gate notifies its overlay, so the
legacy source drops its cached entries and derived album/tag/place lists when the
page publishes another group. The switcher shows the availability label under it:
「Available wallpaper」, or 「Available wallpaper (browsing restricted)」 while the
gallery range narrows browsing; temporarily ignoring the gallery range forces the
first, because browsing is then unrestricted.

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
