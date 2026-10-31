# Grouped wallpaper

A fork-only feature: wallpaper groups, each owning its own visible range, on top
of the Muzei-style live wallpaper mechanism.

## Status

- **Done**: group model, layout invariants, bundled defaults (JSON), storage
  (`wallpaper_groups` table, schema v7; `baseActive` in v9; per-group `effects`
  in v10; per-group `interval`/`ordering` in v11; `grouped_wallpaper_history` in
  v12), controller with the page's
  in-memory draft, the wallpaper-group page reachable from the visible-range
  page's More menu / its own bottom-bar entry, the engine's closed loop (Dart
  baking + native slot queue), global gestures, the immersive view page, per-group
  home/lock effects with a copy-to-other-groups grid, per-group auto-advance
  (interval + ordering, scheduled through the shared WorkManager chain), the
  four-layout notification with photo, group and freeze actions, the
  availability label under the group switcher, the global home-screen scroll
  effect switch, the full set of rule actions on the group page (move to
  base/restriction/supplement, open in a media set by replacing or appending,
  delete), per-permission locking, the usage history (page, notification entry,
  configurable limit), "duplicate group", and the in-app notice that offers the
  wallpaper back after an update made the system drop it.
- **Not done yet**: the notification's copy/share button (shown but disabled),
  filtering the management surfaces (settings, explorer, vaults,
  recycle bin) while a range is locked, temporary/permanent selection ranges,
  Aves Copy, and import/export.

## The bottom-bar entry

The wallpaper is a peer of the visible range, not a hidden sub-page of it, so the
bar derives its own entry instead of writing it into `bottomNavigationActions`:
the user's list stays theirs, and the entry can be closed and reopened.

- `wallpaper.groupedNavMode` (AppMeta) picks one of three placements:
  `shared` (one entry, a shell flipping between the two pages, the original
  setup), `separateLeft` and `separateRight` (its own entry immediately left or
  right of the visible-range entry). The default is `separateRight`.
- `withWallpaperNavDestinations` composes `withVisibleRangeDestination` and
  inserts the entry next to the range entry wherever the user moved it. It
  derives nothing while picking a photo, in `shared` mode, when the entry was
  closed, or when the user pinned `/wallpaper_groups` in their own list.
- `wallpaper.groupedNavEntryClosed` (AppMeta) is the close switch. It lives on the
  wallpaper page's More, and only while the entry is derived: a pinned entry is
  the user's, so the menu leaves it alone. Closing removes the entry the page was
  reached from, so the page hands the screen back to the visible range instead of
  staying on a destination the bar no longer shows.
- The visible range page's More keeps "Wallpaper groups": in `shared` mode it
  flips the one entry's page, and in a separate mode it opens the page through the
  bar's own destination, so the bar highlights the wallpaper entry rather than
  leaving the range entry selected. Opening the page this way reopens a closed
  derived entry first, because a destination the bar does not show cannot be
  highlighted.
- Closing is undone from the visible range page: while the derived entry is
  closed it offers "Show the wallpaper group entry". The close control sends the
  user back there, so the page that receives them owns the way back; a pinned
  entry is managed in the navigation editor instead.
- A tap on a fork page's own entry is a no-op while that page is on top (these
  destinations are pushed, not top-level, so a second tap would stack a copy). In
  `shared` mode the range entry's tap also points the shell back at the range
  page.
- `GroupedWallpaperNavController` caches both values for the bar, which is built
  synchronously and cannot read the database; it loads at startup with the other
  essentials and notifies on every change.
- The default bar is All / Favourites / Albums / Visible range: the video
  shortcut is gone and the range entry is stored like any other destination (so
  the user can move or remove it), while the builder still re-appends it when it
  is missing. Existing users keep their own list.
- Settings → "Visible & wallpaper" collects the switches: the nav mode, the
  notification bar, the history limit, the history page, the scroll effect, the
  gestures page, and the four Muzei confirmations/prefetch options that used to
  sit under "Advanced". The group page keeps the same actions as contextual
  shortcuts; both read one store.

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
5. bakes a cover-cropped PNG per slot — at the wallpaper surface, or at the
   photo's whole width when the scroll effect is on (see below) — plus one effect
   PNG per surface when the group's effects are not identity;
6. writes `state.json` and the slot photos atomically, then asks the renderer to
   reload.

A plain `prepare` skips the bake when the state already holds the full queue for
the saved group, is newer than the group's and the range's `updatedAt`, and was
baked for the current layout (surface size and scroll effect). An app start on an
untouched install costs a database read and a file stat, not a bake.

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

### Scroll effect

The wallpaper can pan with the home pages, the way the static wallpaper's "use
scroll effect on home screen" option does. It is one switch, global to the
grouped wallpaper and on by default; it is not stored per group, because it
changes how every group is baked.

With it on, a frame is `surface.height × photo aspect` wide (capped by the
baker's 4096 texture limit) instead of the surface width, so the renderer's
`0..1` offset walks the whole photo. With it off, the frame is exactly the
surface, which is what the wallpaper always did. The renderer and
`GroupedWallpaperViewport` need no change: a frame that is not wider than the
surface simply has no pan range.

Two guards keep the wider frame honest:

- a launcher that never pans (`onOffsetsChanged` reports `xOffsetStep == 0`)
  gets surface-sized frames anyway, or the sides would only be cropped away; an
  unknown step (no callback yet) follows the switch;
- the lock screen does not pan, so the renderer centers its window (`offsetX`
  `0.5`) instead of leaving it on the last home page.

`state.json` records the layout the queue was baked for (`surfaceWidth`,
`surfaceHeight`, `scrollEffect`). A mismatch re-bakes once, which is what makes
the switch immediate and also fixes rotation or a changed system dimension hint
silently keeping a stretched frame.

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
| Photo actions (unlocked default) | previous / next photo / copy\* / history | switch / previous / next / copy\* / history |
| Group actions (locked default) | previous / next group / freeze / next photo | switch / previous / next group / freeze / next photo |

`*` copy keeps Aves-ST's icon but stays disabled (dimmed, no action) until that
feature exists. **history** opens the usage-history page through the app's
cold-start route, like the notification's content intent. **previous** is greyed
out while the history limit is 0: recording is off, so the engine refuses to step
back and the button would do nothing.

The channel is `grouped_wallpaper_v3`, `IMPORTANCE_HIGH`, no badge, with the
system's default sound and no vibration, like Aves-ST's bar: MIUI hides a silent
notification on the lock screen even when
it belongs to a foreground service. The notification is `setOnlyAlertOnce`, so a
frame update never beeps and only the first post after the service starts alerts.
It is also `VISIBILITY_PUBLIC`, so the group and photo names stay readable on the
lock screen, and ongoing, so it cannot be swiped away.

The channel id is frozen. Some devices only show a channel on the lock screen
after the user marks it as important, and that choice is stored per channel id:
bumping the id would silently drop it and bring back the "no bar on the lock
screen" report. The sound could only change through an id bump, so it is settled
too.

The bar is re-read from `state.json` on every frame load, so the service posts
only when `contentKey` changes: status, group number/name, freeze state, the
history limit (it greys "previous"), button set and the photo on screen.
Re-posting an unchanged bar (hundreds of times a day)
is what made MIUI rate-limit the app and then hide its notifications on the lock
screen (`post_frequency` demoted every post).

`wallpaper.groupedNotification` (AppMeta, default on) is the user's switch. It
travels to the service in `state.json` as `notification`: off means no bar **and no
foreground service**, not a hidden one. The page's More menu toggles it, rewrites
the state and calls the `refreshNotification` channel method, so it applies
without waiting for the next bake. The About page documents that a device may
reclaim a wallpaper with no notification more eagerly, and offers to set the
wallpaper again while it is off.

While a real (non-preview) engine is attached, the service promotes the bar to
its own foreground-service notification (`specialUse`, Android 14+), because MIUI
also hides a silent *non-foreground* notification on the lock screen. Promoting
the already-running wallpaper service is the only form Android 12+ allows:
starting a second foreground service from the background is rejected. The
notification is otherwise posted normally, and dropping the foreground state
(`stopForeground`) is what removes it; turning the grouped wallpaper off does
that before cancelling. With the bar off, the wallpaper is a plain
`WallpaperService` like Muzei's, which has no notification either.

The bar only exists while this service is the wallpaper the system is showing:

- `onDestroy` sets a `destroying` flag before clearing the bar. `super.onDestroy()`
  tears the engines down afterwards, and their `onRealEngineDestroyed` callback
  used to post the bar again — a bar that then stayed in the shade after the
  wallpaper was replaced.
- The plain (non-foreground) path checks `WallpaperManager.wallpaperInfo` first, so
  the picker preview and an engine that outlived a replacement post nothing. The
  foreground path is exempt on purpose: some devices report `wallpaperInfo` late,
  and a wrong answer there would keep the bar off the lock screen.
- A service the system or the OEM kills never runs `onDestroy`, so the app cancels
  a leftover bar itself: `GroupedWallpaperEngine.attach()` (app start and the
  background refill worker) calls the `cancelNotification` channel method when the
  service is no longer the system wallpaper. A live instance is left alone, since
  it owns its bar and clears it on the way out; only a bar whose service is gone is
  a leftover.

Tapping the body opens the immersive view of the photo on screen, exactly like
the three-finger gesture: the app pushes the shared bottom-bar destination
(`/visible_range`, rendering the wallpaper page on the playing group) below the
view, so backing out lands on the wallpaper page with its entry highlighted. The
expanded first button only switches the button set. The screen broadcasts
(`ACTION_SCREEN_OFF`, `ACTION_SCREEN_ON`, `ACTION_USER_PRESENT`) switch the layout
family and the home/lock effect image together, and return the button set to the
keyguard's default.

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

### Usage history

`grouped_wallpaper_history` (schema v12) records the photos the wallpaper put on
screen, so the user can look back at them and step to the previous one.

- **Recorded when the photo changes**: an advance, "previous", a group switch or
  a promotion the renderer made on its own. A layout re-bake, a freeze/resume, an
  off switch, a lock or a failure keeps the same entry and adds no row.
- **Per photo, per group**: the unique key is `(entryId, groupId)`, so showing the
  same photo again only moves its `usedAt` to the front, while the same photo in
  another group is a different wallpaper and keeps its own row. The row stores the
  group name/number as a snapshot, so it still reads correctly after the group was
  renamed or deleted.
- **Limit**: `wallpaper.groupedHistoryLimit` (AppMeta, 0–1000, default 200). `0`
  turns recording off and greys the notification's "previous" button, and the
  engine's `previousArtwork()` becomes a no-op. Changing the number **never
  deletes** anything: the next recorded photo prunes the oldest rows beyond the
  limit, and only "clear history" removes rows.
- **Where it lives**: `/grouped_wallpaper/history`, reachable from the group
  page's More, the view page's More and the notification's "history" button (an
  activity intent, not a broadcast). Rows whose photo left the library are
  skipped, and tapping one opens the viewer. The photos are read from the
  database by id (`localMediaDb.loadEntriesById`): the paged browsing engine never
  materializes entries in `CollectionSource`, so looking them up there returned
  nothing and left the page permanently empty.
- **Scoped to a group**: the page shows the group it was opened from (the group
  page's selection, the view page's playing group, or the group in `state.json`
  for the notification and a cold start), with the group name under the title.
  More → "switch group" lists **every** group with its record count, so an empty
  group reads as empty instead of broken. A locked range hides that entry: reading
  another group's photos is exactly what the lock prevents.
- **Clearing is all-or-nothing**: "clear history" empties every group, not just
  the one on screen. The confirmation carries a "do not ask again" box
  (`wallpaper.groupedHistoryClearSkipConfirm`); once skipped, the menu keeps a
  checked "confirm before clearing" entry to turn it back on, since the dialog can
  no longer offer the box.
- The limit travels in `state.json` (`historyLimit`) for the same reason as the
  switches above: the native bar owns the greyed button.

### Duplicating a group

The group page's More menu copies the selected group into a new one. The copy is
deep: base, rules (new ids, same content), order, permissions, effects, interval
and ordering. It is never enabled, current or locked, and it is selected right
after, so the user can edit it immediately. A **locked** group is refused (in the
page and again in the controller): its range is read-only, so a copy would clone
what the user froze. The copy is a draft change like any other, so it disappears
on "discard changes".

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
right. The menu has 「Open wallpaper groups」, 「Open in gallery」, share and
「Usage history」. A
wallpaper gesture has no Activity, so the view is pushed over the playing
group's page, itself over the app's home page: back walks view → group page →
home instead of closing the app, and the group page starts on the group being
played. Opened from the group page, 「Open wallpaper groups」 pops back to it.

The page below the view is the shared bottom-bar destination
(`VisibleRangeShellPage` with `visibleRangeDestination` set to the wallpaper
page), not the standalone `/wallpaper_groups` route: that way the bar highlights
the entry the user is on instead of falling back to its first item, and the
page's own menu keeps working the same way it does from the bar. The
notification's body opens the same view, so both entry points land identically.

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

### Another wallpaper replacing this one

The system keeps a single wallpaper, so setting another one (live or static), or
an app that changes the wallpaper on a schedule, silently replaces the grouped
wallpaper: the service is destroyed, the bar goes away with it, and the gestures
stop working. That is not the feature being killed in the background, and the
log shows it as an external `WALLPAPER_CHANGED` right before `service.destroy`.

`groupedWasActive` (AppMeta) records that this wallpaper really has been the
system wallpaper, because a `state.json` alone cannot tell a replaced wallpaper
apart from one that was never set (the page prepares frames for the picker's
preview too). When the page opens and the wallpaper is no longer active, has a
frame, is not turned off and that marker is set, it warns once and clears the
marker. The warning's checkbox starts checked and writes
`groupedOverwriteDismissed`, so the default answer is "do not tell me again".
Setting the wallpaper again from the page is the fix, and the About page says so.

The native side lives in
`android/app/src/main/kotlin/deckers/thibault/aves/features/grouped_wallpaper/`
and uses its own state root (`filesDir/grouped_wallpaper`), so it shares no files
with Muzei. It never touches the database.

#### An update that resets the wallpaper

AOSP rebinds the component when the package is replaced, but some OEM builds
(MIUI observed) reset the wallpaper to their default instead, so every app update
stops the wallpaper. Nothing in the app can rebind it silently:
`SET_WALLPAPER_COMPONENT` is `signature|privileged`, and a normal install is
refused with a `SecurityException` even through reflection. Muzei answers the
same problem the same way, by checking on entry and offering one tap to re-apply;
it has no boot or package-replaced receiver either.

So the restore has two channels, and both start from one decision:

- `GroupedWallpaperRestore.restoreIfLost` runs from `MainActivity.onCreate` (a
  force-stopped package receives no `MY_PACKAGE_REPLACED`, and MIUI does not
  deliver it either) and from the receiver on builds that do. Where the
  permission happens to be granted it binds the component; otherwise it posts a
  one-tap notification.
- `GroupedWallpaperRestore.restoreOffer` is the same decision, side-effect free,
  exposed on the channel and polled by `GroupedWallpaperRestoreNotice`. It drives
  `GroupedWallpaperRestoreBody`, the strip on the collection and filter-grid
  pages, because an OEM that resets a wallpaper also tends to silence the app's
  notifications (MIUI: every post of this app muted), so a notification is not
  what the user reads. Applying from the strip opens the system picker; the
  answer is re-read on every resume, so a committed switch drops the strip.

The decision only fires when the wallpaper was in use (`state.json` recent and
not `disabled`/paused), the component is not ours, no *other* live wallpaper is
bound, and no static wallpaper file exists. That last pair is what keeps the
notice from nagging a user who picked another wallpaper, and the OEM's fallback
is distinguishable because after a reset the system keeps no wallpaper file.

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
only works on what is already there: it shows, toggles, renames, moves a rule to
another section or to the base, opens it in a media set (replacing or appending),
and deletes it. Older builds materialized that catalogue into every group; it is
pruned on every start (not only on a defaults bump), so a restored backup cannot
bring it back.

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

The rule actions (move to base/restriction/supplement, delete) and the detailed
lock are drafts too: they change what the page shows and are written, with
everything else, by **Save changes**. Opening a rule in a media set writes
nothing.

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

The gallery range and a group range are independent data sets, and both constrain
browsing. The group page publishes the range of the group it shows through
`VisibleRangeGate`, so the media set, albums, search and every other browsing
surface see the gallery range **and** the group range — exactly the photos the
wallpaper may use. The intersection is the default on purpose: a user may have
restricted the gallery for privacy and still hand the phone over to show the
wallpaper, so the page must not widen what the gallery hides. It is also the way
to see which photos the configured groups actually contain, so it does not depend
on the live wallpaper running or on which group is playing: only on the group the
page has selected.

The scope is app-wide, like the gallery range, and lives until the user selects
group 0, closes the page or its entry, or the process dies. A destination switch
removes the page but keeps the scope: the navigation layer marks that `dispose`,
which is what lets the media set resolve against the group. The scope is
in-memory only, so a process restart starts on group 0 (or adopts the group the
wallpaper is running) and never leaves browsing unexpectedly restricted. The live
wallpaper never reads the gate: it uses the saved group range through
`wallpaperMediaSetFilter`, so gallery browsing can never narrow the wallpaper
result.

The page can temporarily ignore the gallery range while it is open; that choice
is published in the same overlay, so the media set's strip flips the same switch.
Ignoring a locked gallery range asks for its password first, and restoring never
does. It is a view choice, never a write: clearing the scope restores the range.

All three browsing paths ask the same gate — the paged predicate, the summary
query and the legacy in-memory scan — so the album list, the album counts and a
media set opened from either path agree. The gate notifies its overlay, so the
legacy source drops its cached entries and derived album/tag/place lists when the
page publishes another group. The switcher shows the availability label under it:
「Available wallpaper」, or 「Available wallpaper (browsing restricted)」 while the
gallery range narrows browsing; temporarily ignoring the gallery range forces the
first, because browsing is then unrestricted.

Locking a group (`group_lock_rules.dart`, persisted in AppMeta) freezes the
switcher to group 0 and the locked group, disables edits to the locked group's
range, group management and pinning into groups, and makes the engine write
`switchLocked` into `state.json` so the notification's group buttons grey out. It
does not prevent closing the page: that only removes the browsing scope, while the
lock and its group survive a restart until the password unlocks them.


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
