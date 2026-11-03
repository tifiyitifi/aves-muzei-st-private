# Grouped wallpaper

A fork-only feature: wallpaper groups, each owning its own visible range, on top
of the Muzei-style live wallpaper mechanism.

## Status

- **Done**: group model, layout invariants, bundled defaults (JSON), storage
  (`wallpaper_groups` table, schema v7; `baseActive` in v9; per-group `effects`
  in v10; per-group `interval`/`ordering` in v11; `grouped_wallpaper_history` in
  v12; `separateLockRange` and the history `surface` in v13; the shared condition
  pool in v14), controller with the page's
  in-memory draft, the wallpaper-group page reachable from the visible-range
  page's More menu / its own pinned navigation destination, the engine's closed loop (Dart
  baking + native slot queue), global gestures, the immersive view page, per-group
  home/lock effects with a copy-to-other-groups grid, per-group auto-advance
  (interval + ordering, scheduled through the shared WorkManager chain), the
  history walk behind the notification's previous/next controls (both neighbours
  baked and cached, so a step never waits for a bake), the
  four-layout notification with photo, group and lock actions, the
  availability label under the group switcher, the per-group home-screen scroll
  effect (edited in the effects page), per-group image framing (auto rotation of
  landscape photos plus screen fill / fit / stretch, also edited in the effects
  page), the full set of rule actions on the group page (move to
  base/restriction/supplement, open in a media set by replacing or appending,
  delete), per-permission locking, the usage history (page, notification entry,
  configurable limit), "duplicate group", the in-app notice that offers the
  wallpaper back after an update made the system drop it, and the device
  capability probe that warns once before applying and bakes surface-sized
  frames when the home screen cannot host or pan the wallpaper.
- **Not done yet**: the notification's copy/share button (shown but disabled),
  filtering the management surfaces (settings, explorer, vaults,
  recycle bin) while a range is locked, temporary/permanent selection ranges,
  Aves Copy, and import/export.

## Split lock surface (home / lock)

A group may draw a different wallpaper on the lock screen than on the home
screen. The lock surface is a **decoy**: it exists so whoever sees the lock
screen does not learn which group the home screen is playing. A user can keep a
private group at home and a public one on the lock screen, and landing on the
lock screen then masks the home wallpaper without changing it. Two consequences
shape the design:

- the lock screen always draws the **lock range**, and an unknown or failed
  state never falls back to the home photo (fail closed);
- the notification's priority on the lock screen is **switching groups**, not
  changing the photo.

**One condition pool, two marks.** A group stores its conditions once: the single
`wallpaper`-scope range row (`<groupId>.range`) is its pool, and every base/rule
carries a `surfaces` bit mask (`1` home, `2` lock; the base's mask is
`baseSurfaces`). Home and lock are *projections* of that pool
(`projectWallpaperGroupRange`), with the historical per-surface ids, so
`state.json`, the decoy range id and the history keep addressing the same
ranges. The page lists each condition once with two marks; only the lamped
surface is edited, and tapping a tile switches that surface's mark.
`mergeWallpaperGroupRange` folds an externally written projection back into the
pool without disturbing the other surface; it is kept as the compatibility path
for a writer that still addresses a single surface, while the pin sheet and the
write-back list write the pool itself (see *Pinning*).

- **Seeding the split.** Turning the switch on the first time marks every
  condition the home surface uses for the lock surface too, so the two start
  identical; `lockRangeSeeded` remembers that and later toggles only hide the
  lock marks, so the narrowing the user made survives.
- **Prepared before activation.** The split and the H/L marks are stored data,
  not a request to turn the wallpaper on: they can be configured while the
  grouped wallpaper is off, and the engine picks them up when it becomes the
  system wallpaper. The device-support check (`lockSurfaceStatus`) and the
  wallpaper-chooser dialog only run while this wallpaper is actually active,
  because that is the only time the answer means anything. When it is active,
  toggling the split re-bakes at once instead of waiting for "save changes".
- **One frame, not a queue.** The decoy advances only with time, so it has a
  single baked file (`state.json` `lock`) instead of the home queue's three
  slots. It is baked at the surface size with the group's lock effects already
  applied: no scroll-wide frame, no pan centering, no prewarm, no rewind stack.
- **No gesture, and no bar photo step.** A double tap or a three-finger tap on
  the lock screen is ignored, and the bar greys its photo button there (the
  group buttons stay live, because switching groups is the lock surface's
  priority). The app's view page has a home/lock switch, and its previous/next
  controls are the only manual way to step the decoy — they work before the
  decoy has a frame, so the first step bakes one.
- **The walk is per group and self-healing.** A record that left the range, or
  that belongs to a group the user switched away from, is skipped when stepping
  back, and dropped once nothing older can be shown, so "previous lock photo"
  never stays a dead button.
- **Shared interval.** The group's interval advances both surfaces in one run.
  An interval run picks a new decoy photo; a home "next photo" does not touch
  the lock surface (a home change advances the home queue only, and
  `_syncLock` keeps the decoy's entry unless it is missing or the range moved).
- **History by surface.** `grouped_wallpaper_history.surface` splits the
  records, and the history page's More menu filters by surface. Clearing still
  clears everything.
- **Battery.** A scheduled advance is applied only while the wallpaper is
  visible (home or lock) and the screen is interactive. Otherwise the run is
  deferred: the advance is marked pending, the next countdown is armed, and a
  catch-up run starts the moment the surface is shown again. A two-hour video
  therefore costs zero bakes instead of a dozen.
- **Detection.** From Android 14, `getWallpaperInfo(FLAG_LOCK)` reports whether
  the lock screen draws a live wallpaper. The page warns when the decoy cannot
  be shown (`none`/`other`); older devices answer `unknown` and only the About
  text explains the limit.
- **Migration v14.** The old lock range row is folded into the pool: identical
  conditions merge into one row marked for both surfaces, a lock-only rule moves
  into the pool row marked for the lock surface, an identical base is marked for
  both, and a *different* lock base becomes a lock-only restriction (an
  unrestricted base AND those filters is the same range).



## Navigation

The wallpaper page is a navigation destination of its own, not a sub-page of the
visible-range editor, but the bar keeps it **off by default**: it is a settings
page that is rarely opened.

- **Entry policy** (`wallpaper.groupedNavMode`, AppMeta, edited in Settings →
  Visible & wallpaper → "Wallpaper page"): `shared` puts both pages behind the
  visible-range entry (the entry keeps one slot, its icon and label follow the
  page it renders), `separateLeft`/`separateRight` give the wallpaper page its
  own entry beside the range entry. The default is `separateRight`.
- **Temporary, not persistent.** The separate entry is derived only while the
  wallpaper page is on screen (`GroupedWallpaperNavController.pageVisible`): with
  a four-entry bar, opening the page shows five and leaving restores four. The
  depth counter survives a page replaced by another one, where the new page
  starts before the old disposes. The shared mode never changes the count.
- The visible range page's More opens the page with `AvesNavItem(route).goTo(
  topLevel: true)`, the same navigation a bar destination performs, so the stack
  is replaced and the temporary entry is highlighted. In the shared mode it flips
  `visibleRangeDestination` instead, keeping the single entry selected.
- A user who pinned `/wallpaper_groups` in their own list owns the entry: it is
  permanent, and no second one is derived.
- **Closing is the counterpart of opening.** The wallpaper page's More ends with
  "Close wallpaper page" in every mode. An unsaved draft is never dropped
  silently: the dialog offers Save (applies the draft and re-bakes), Discard and
  Cancel. Closing clears the group's browsing scope, so the gallery returns to
  its own visible range. In the shared mode it flips the one entry back to the
  range page, icon and label included; with a temporary entry it navigates to the
  range page and the page's `dispose` takes the entry away. A pinned entry stays,
  because it is the user's own navigation item.
- Notifications, the three-finger gesture and session restore deep-link the route.
  In the shared mode the deep link is routed through the shell
  (`VisibleRangeShellPage`, which passes `promptUnlock` on) so the bar still has
  an entry to highlight; the unlock route keeps its reason for prompting.
- The default bar is All / Favourites / Albums / Visible range: the video
  shortcut is gone and the range entry is stored like any other destination (so
  the user can move or remove it), while the builder still re-appends it when it
  is missing. Existing users keep their own list.
- Settings → "Visible & wallpaper" collects the switches: the wallpaper page
  entry policy, the notification bar, the lock switches, the history limit, the
  history page, the gestures page, the photo-change animation, the frame
  retention, and the four Muzei confirmations/prefetch options that used to sit
  under "Advanced". The group page keeps the same actions as contextual
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
5. bakes a cover-cropped frame per slot — at the wallpaper surface, or at the
   photo's whole width when the scroll effect is on (see below) — plus one effect
   PNG per surface when the group's effects are not identity;
6. writes `state.json` and the slot photos atomically, then asks the renderer to
   reload.

The pixels are baked natively: `GroupedFrameWriter` decodes and cover-crops with
Glide, encodes WebP and writes `photo.webp` itself, so no full-size image crosses
the channel (only its size and a 64×64 darkness sample come back). Dart still
owns *which* photo, the cache key and the state files, and it keeps a complete
fallback (`SkiaFrameBaker`) for hosts without the service, video and SVG entries,
and any decode the platform refuses. The effect pass stays in Dart on both paths:
the effects page previews it on the GPU with the same math, so a second
implementation would let the preview and the wallpaper drift apart.

A plain `prepare` skips the bake when the state already holds the full queue for
the saved group, is newer than the group's and the range's `updatedAt`, and was
baked for the current layout (surface size and scroll effect). An app start on an
untouched install costs a database read and a file stat, not a bake.

### The navigation queue

`state.json` carries `previous → current → next`, both neighbours baked, so the
renderer can step in *either* direction without waiting for Flutter: a wallpaper
tap goes forward, the bar's "previous" goes back, and each switch draws a texture
it already uploaded. The renderer writes the step to `runtime.json` synchronously
and asks the app (or the shared background worker) to refill the frame it left
behind. A tap that arrives before the neighbour is uploaded is buffered (capacity
5, 15 s expiry) and replayed as slots land; the expiry is logged, so a dropped
tap is countable instead of silent.

Dart adopts a runtime only when it names a queued neighbour of the state it knows,
and re-reads it just before writing `state.json`, so a step that landed during a
bake is not rewound. The renderer does the same on reload: if the new state's
`next` is the slot on screen, it keeps that slot and rewrites the runtime with the
new generation. Without that, a tap could show the next photo and then snap back
to the one it just left.

The walk itself is the usage history (see below): a forward step returns through
the records the user already saw and only creates a new photo at the newest one.
Both directions are the same code path ([`_moveTo`]), so stepping back and forth
can never reorder the records or skip one.

### Frame retention

A reload only drops the frames the new `state.json` no longer names. Judging a
frame stale because *this* reload did not decode it is what blanked the wallpaper
and made taps go unanswered: the loader deliberately skips a slot whose
`(entryId, photo)` is already on the GPU, so the decoded set says nothing about
which textures are alive. The rule lives in `GroupedTextureRetention`:

- the new state's slots survive, as does the slot on screen (and the one still
  fading out) whatever the state says, because nothing would replace them;
- a slot that left the queue, or whose `(entryId, photo)` changed (a re-bake, or
  a home↔lock effect switch), is dropped.

The renderer keeps the state's intent (`desired`) apart from the slot it really
draws (`displayed`, which is what `displayedSlotId()` and therefore the
three-finger view and the bar report). When the wanted slot's texture is missing a
reload falls back to a neighbour, but the fallback is temporary: the next reload
that uploads the wanted slot restores it (`display.restore`). A slot whose file
exists but whose texture still does not appear is retried at most three times per
`(generation, desired)` and then logged as `texture.giveup`, so a corrupt bake
cannot reload in a loop; a decode that returns nothing logs `decode.null` instead
of disappearing silently.

A reload can also race two things, and both used to leave the wallpaper on the
previous photo:

- **the state writer**: a state older than the one on screen (`generation` lower)
  is discarded, so retention never treats the newer slots as garbage;
- **a frame that went away while a reload ran**: the loader's skips were checked
  against `uploaded` from a context that no longer draws. The decoded bitmaps are
  context-free, so they are uploaded as usual and a follow-up reload fills the
  slots the stale snapshot skipped. The epoch still pairs with the snapshot, so a
  reload is never judged against frames it did not have.

`uploaded` and `readySlots` are derived from `textures` by one function
(`publishFrames`): a map that drifts from the textures would make the next reload
skip a slot that has no texture and leave a hole.

#### What a surface rebuild invalidates

`onSurfaceCreated` is a *window* event, not a guarantee of a new EGL context. The
vendored `GLWallpaperService` keeps one context for the life of the engine
(`EglHelper.start()` reuses it and `finish()` only runs when the GL thread exits),
so a hide/show keeps every texture id alive. The renderer therefore asks the
driver which frames survived (`glIsTexture`) instead of clearing them all; only a
frame that is really gone is dropped, and only then is the epoch bumped and a
re-decode requested. Clearing on every surface was what showed the grey
placeholder each time the launcher recreated its surface. The same probe rebuilds
the shader program and the placeholder texture only when they are gone.

#### The retention switch

**Settings → Visible & wallpaper → Frame retention** caps how many baked frames
stay resident. The frame on screen is kept whatever the value, which is why the
placeholder never comes back from this switch:

- **Auto** keeps every frame, except when the group's home scroll effect is on:
  those frames are `surface.height × aspect` wide (up to 4096), so two extra ones
  are the expensive case;
- **Keep all frames** (default) is what every earlier build did: an instant tap,
  and the highest GPU memory use;
- **Keep the frame on screen only** decodes a tap's target on demand, so the tap
  waits for one decode.

The value is global (`wallpaper.groupedFrameRetention`) and travels in
`state.json` as `frameRetention`, because the renderer decodes and evicts frames
on its own. `scrollEffect` travels with it so the renderer can resolve `auto`
without asking Dart. A limited reload decodes the frame about to be shown first,
then a buffered tap's target, and steps back to "keep everything" for that round
when the wanted frame cannot be decoded: a neighbour is the only alternative to
the placeholder.

### Crossfade

A promoted photo fades over 300 ms (Muzei uses 750 ms for its slower
blur-to-sharp switch). The outgoing frame keeps its texture until the incoming
one is fully opaque, so a mid-fade reload can never blank the wallpaper, and a
tap during a fade starts a new one instead of queueing behind it. Two things turn
it off: the system animation switch (`ANIMATOR_DURATION_SCALE`), which is what
motion-sickness settings flip, and the user's global "photo change animation" in
**Settings → Visible & wallpaper**, which travels in `state.json` as
`transitionMs` (`0` switches instantly). It is deliberately not a group effect:
a fade runs between frames that may belong to different groups, and the effects
blob is the frame cache key, so a duration there would invalidate every frame.

### Frame cache

Every baked frame is stored under `frames/<entryId>/<key>/`, where `key` is the
target size plus a fingerprint of the group's effects. A frame is therefore owned
by *the photo at that layout*, not by the slot that happens to draw it, so any
step back to a photo shown before is a file reference instead of a decode, an
effect pass and an encode. Frames written by the native baker are `photo.webp`; a
`photo.png` from an older build is still a cache hit, so the format changed
without a migration. The cache keeps the 24 most recent frames (or the history
limit when smaller), never evicts the frames the queue references (nor the one
baked ahead of it), and is trimmed when the limit changes and cleared with the
history. Two extra measures keep a switch invisible: the renderer skips decoding
a slot whose `(entryId, photo)` it already uploaded, and the engine reuses the
queued slot's id, so a back-and-forth between two records is a texture swap.
Every write stages a `*.tmp` and renames it over the destination, so a crash can
leave one behind inside a kept key directory, where directory-level eviction
never reaches it: `attach()` sweeps `*.tmp` files older than 30 minutes (a fresh
one may be the other engine's live write) from the root, `tmp/` and the cache.

After a settle at the newest record the engine also bakes the frame the *next*
forward step will want (`_prewarmNext`). It is a cache entry only: no cursor, no
rewind entry and no `state.json` write, so history and previous/next are
unaffected; the second tap of a burst then finds its frame on disk.

A slot that left the queue is still on disk in the cache: this is why "previous"
is instant while the frames are within the cache depth, and only the frame beyond
it is baked once more.

### Tap detection

`onCommand(COMMAND_TAP)` fires for *every* tap, single ones included, so a
launcher's command cannot tell a single tap from a double tap on its own. The
service feeds both that command and the gesture detector's `onDoubleTap` into
`GroupedTapGate`, which only fires when a second signal arrives inside the
platform's double-tap window and stays closed for 250 ms afterwards (long enough
to swallow the third signal of one gesture, short enough for two quick double
taps to both count). A single tap therefore never changes the wallpaper, a real
double tap fires once whichever path reports second, and a launcher that delivers
no touch events still works through its two commands. Each signal logs
`tap.signal src=touch|command fired=…` so a future report can tell a gesture the
gate ate from one that never arrived.

A double tap advances the **home** queue only: the lock decoy has no gesture and
`_syncLock` keeps its entry unless it is missing or its range moved. The lock
photo changes on the group's interval, or from the view page's previous/next
controls. A manual home step additionally restarts the auto-advance countdown
(`restartAutoAdvance`), which the About text lists as a known limitation.

A gesture that opens a page passes the service's own context to
`GroupedWallpaperAppBridge`: an app-provided context would still be null when the
wallpaper fires before the app ever ran, which used to drop the gesture without a
trace. The split-lock gate asks `KeyguardManager.isKeyguardLocked` at gesture
time instead of trusting the cached broadcast state, so a missed
`ACTION_USER_PRESENT` can no longer swallow every gesture.

**Another live wallpaper can intercept the gesture.** Multi-finger touches are
delivered to whichever live wallpaper is active, and an app that keeps its own
service (Muzei, for example) may still consume them after this wallpaper is set,
so the three-finger tap silently does nothing. Setting this wallpaper again, or
clearing the other app's data / uninstalling it, hands the gesture back. Both the
group page's About text and the gestures hint state this; there is nothing to fix
in this code, and the notification still opens the view page.

### Scroll effect

The wallpaper can pan with the home pages, the way the static wallpaper's "use
scroll effect on home screen" option does. The switch lives with the group's
effects (`WallpaperEffectsConfig.homeScrollEffect`, on by default), so a group
can pan while another stays still; it is edited in the effects page's **Home**
tab and there is deliberately no lock counterpart, because the lock screen never
pans. Groups written before the switch moved into the group read the old
app-wide `wallpaper.groupedScrollEffect` value once, so an upgrade keeps the
user's choice.

With it on, a frame is `surface.height × photo aspect` wide (capped by the
baker's 4096 texture limit) instead of the surface width, so the renderer's
`0..1` offset walks the whole photo. With it off, the frame is exactly the
surface, which is what the wallpaper always did. The renderer and
`GroupedWallpaperViewport` need no change: a frame that is not wider than the
surface simply has no pan range.

Two rules keep the wider frame honest:

- the switch is the user's, but it is only half the answer. `_effectiveScrollEffect`
  also asks `WallpaperCapability`: a device that cannot host this service on the
  home screen, or a launcher that reports it never pans, is baked at the surface
  size instead. The capability is deliberately conservative — an unmeasured
  device (no offset callback yet, or a service that is not bound) keeps the wide
  frame — because a wrong "unsupported" would silently take the effect away from
  a phone that does pan;
- the lock screen does not pan, so the renderer centers its window (`offsetX`
  `0.5`) instead of leaving it on the last home page.

`state.json` records the layout the queue was baked for (`surfaceWidth`,
`surfaceHeight`, `scrollEffect`). A mismatch re-bakes once, which is what makes
the switch immediate and also fixes rotation or a changed system dimension hint
silently keeping a stretched frame.

### Capability

`WallpaperCapability` (`model/wallpaper_capability.dart`) is the one place that
decides what the device can do. The native `capability` channel method answers in
one call, because the page and the engine need the same facts at different times:

| field | source | meaning |
|---|---|---|
| `host` | `getWallpaperInfo(FLAG_SYSTEM/FLAG_LOCK)` vs our service | `home`, `lock`, `both` or `none` |
| `launcherPackage` | `resolveActivity(ACTION_MAIN/CATEGORY_HOME)` | the default home package |
| `deviceModel` | `Build.MODEL` | remembers which devices were warned |
| `scrollSpan` | `Settings.Secure pref_key_wallpaper_screen_scrolled_span` | MIUI's "scroll wallpaper" switch, null elsewhere |
| `scrollStep` | the service's last `onOffsetsChanged` | `-1` → unknown, `0` → never pans, `> 0` → pans |
| `scrollOffsetMoved` | whether `xOffset` ever changed between callbacks | proves panning even when the step stays `0` |

`panVerdict` order (a positive answer always wins):

1. `host == lock` → unsupported (that host never receives offsets);
2. `scrollStep > 0` → supported;
3. `scrollOffsetMoved` → supported (some launchers scroll while reporting no step);
4. `scrollSpan == 0` → unsupported;
5. `scrollStep == 0` → unsupported;
6. otherwise → unknown.

`hostVerdict` only drives the pre-apply warning, never the frame. It is
unsupported when the launcher is a known fixed-wallpaper one (currently
`com.miui.home`) and the home screen is not running our service. The list is
intentionally short: a wrong entry costs one dismissible dialog, and entries are
added only with evidence.

`bakesWide` is `panVerdict != unsupported`. The behaviour matrix is therefore:

| device | switch | host | frame |
|---|---|---|---|
| pans | on | home/both, step > 0 or moving offset | wide |
| pans | off | any | surface |
| HyperOS lock-only | on | lock | surface |
| launcher never pans | on | home/both, step = 0, offset fixed | surface |
| not measured yet | on | none or step unknown | **wide** |

The last row is the rule that protects a panning phone: unknown never narrows.

Two paths make the decision converge without the user re-applying:

- the launcher's offset callbacks feed `recordOffsets`. It reports a change when
  the panning answer leaves "unknown" (the first callback), when the step crosses
  zero in **either** direction, or when the offset starts moving; the service
  then asks for one refill, so `> 0 → 0` drops the wide frame and a moving
  offset brings it back;
- a host that only draws the lock screen never gets an offset callback at all,
  so the page's `_refreshEngine` asks for one `prepare()` when the state says
  wide but the capability says unsupported. `_isLayoutStale` makes every later
  probe a no-op.

The pre-apply warning is stored in AppMeta under
`wallpaper.groupedCapabilityWarned` as `<model>|<launcher>`, so it appears once
per device and again after a launcher change. `host == lock` also changes the
page's status line to "Running on the lock screen only", and the effects page
notes that the launcher does not pan while leaving the switch usable.

### Effects

Effects belong to the group, with separate home and lock values and Muzei's
optional link toggle. They are stored as one JSON column on the group row
(`effects`, schema v10), so an upgraded group reads the identity configuration
and keeps its photos sharp.

The baker applies the same math as Muzei (blur at a quarter of the frame,
greyscale matrix, dim from the artwork's own darkness) and writes
`frames/<entryId>/<key>/home.png` / `lock.png` next to the sharp `photo.webp`. A
real blur is baked at that quarter size and the GPU scales it back up, exactly as
Muzei does; dim and grey alone stay full size, because downscaling them would
visibly soften the photo. An identity effect leaves the path empty, so the
renderer falls back to the sharp file instead of a second copy. The native
renderer picks the file for the surface being drawn, using the keyguard state, so
only one texture per slot is uploaded. The `key` includes the effects, so editing
them re-bakes every frame at the new rendering instead of showing a stale one.

The effects page is bound to the viewed group and applies as the sliders move,
bypassing the range draft: effects are display preferences, and the live
wallpaper should follow them without a separate "save". Its copy action opens a
group grid with the app-wide XOR-range gesture and writes the same configuration
to every selected group in one transaction.

The page is three panels, in a deliberate order: **blur and tone** (the sliders
plus the link toggle), the small **auto-advance** row (a group-level setting
shared by both surfaces), and **image adaptation** (the scroll switch together
with rotation and fit, which it gates). Rare actions — copy to other groups,
Muzei defaults, reset to zero, and the effects manual — live in one overflow
menu, so each has both an icon and a label instead of a bare glyph (the reset
glyph read as "history"). The manual page explains the model a slider cannot:
per-surface storage, when a change reaches the wallpaper, why a wide home frame
ignores adaptation, and the 90° rotation rule.

### Framing (rotation and image fit)

Each surface also owns a framing: a rotation and an image fit, stored in the same
`effects` JSON as `framingHome`/`framingLock`, so no schema migration was needed
and an upgraded group reads the identity framing. The link toggle deliberately
does not cover it: the two surfaces judge their own orientation.

- **Order is orientation first, then fit.** A frame is rotated and only then
  mapped onto the surface, so choosing "stretch" never changes which photos are
  rotated.
- **Fit** is `fill` (cover, the historical behaviour), `fit` (contain, with opaque
  black bars) or `stretch` (each axis independently).
- **Rotation** is `off`, `clockwise`, `counterClockwise` or `random`. Only the
  *direction* is the user's: whether a photo is rotated is decided per photo.
- **The decision.** With the oriented photo aspect `a` and the surface aspect
  `s`, cover/contain prefer the orientation whose aspect is closest to the
  surface (`|ln(a/s)|`), and stretch prefers the one with less distortion — the
  same comparison. The rotated candidate (`|ln(1/(a·s))|`) must be closer by
  `2·ln(1.2)` (`wallpaperRotationMargin`): on a typical phone that is a
  landscape photo of at least `1.2:1` (`wallpaperRotationAspectThreshold`, a 44%
  larger visible area), and a landscape surface rotates portrait photos
  symmetrically. A square surface is neutral, and nearly square photos are left
  alone.
- **Random** draws at *selection* time: the slot (and the lock decoy) carries a
  `rotationSeed`, and the direction is derived from it. A re-bake (an effect
  slider, a layout change, a step back through the history) therefore never flips
  the photo that is on screen, while the next photo draws again.
- **The scroll effect wins.** A wide home frame already has the photo's own
  aspect, so the home rotation and fit are ignored while the launcher pans (the
  controls are greyed but keep their values); the lock screen never pans, so its
  framing always applies. A default lock framing reuses the wide home base, as it
  always did; a custom one bakes a second surface-sized base and a `lock.png`
  even for the identity effects.
- **Baking** applies the geometry natively in `GroupedFrameWriter` (`FrameFit` is
  a host-tested pure object; Flutter's `BoxFit` is the same math) and in the Dart
  fallback, before the effects. The effect pass stays in Dart, and the cache key
  includes the resolved geometry, so a framing edit misses the cache instead of
  showing the previous rendering.
- **Effects edits keep the photo.** `setEffects` bumps the group's `updatedAt`;
  the engine now treats that as a pixel-only change and re-bakes the photo on
  screen, instead of starting the walk over and replacing the picture on every
  slider change. A range edit still starts over (`range.updatedAt`).
- The effects page previews the baked frame (the home base with live GPU effects,
  the final lock image as-is), so rotation, fit and a random direction are
  exactly what the wallpaper draws.

### The notification

`GroupedWallpaperNotification` (Kotlin) posts an ongoing notification while the
grouped service is the system wallpaper, styled after Aves-ST's foreground
wallpaper bar: a coloured group-number badge, the group name and the photo title,
plus borderless actions. The button set follows the keyguard and the user's
default, and the expanded layout's first button switches between the two sets:

| | Collapsed (4) | Expanded (5) |
|---|---|---|
| Wallpaper actions (unlocked default) | previous / next photo / copy\* / history | switch / previous / next / copy\* / history |
| Group actions (lock screen, or selected default) | previous / next group / lock / next photo | switch / previous / next group / lock / next photo |

**Notification buttons** (Settings › Visible & wallpaper) picks the unlocked
default: `wallpaper` (the row above) or `group`. The lock screen ignores it and
always shows the group actions — leaving the group the lock protects is exactly
what a stray lock-screen tap must not do. The value travels in `state.json` as
`notificationActions`, so the bar picks its set without asking the app, and a
changed setting re-posts it at once.

`*` copy keeps Aves-ST's icon but stays disabled (dimmed, no action) until that
feature exists. **history** opens the usage-history page through the app's
cold-start route, like the notification's content intent. **previous** is greyed
out when the rewind stack has no older record: recording is off, the stack is
empty, or the cursor already reached the oldest photo. **next** stays enabled as
long as the group has another photo or the cursor can move forward in the stack.

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
only when `contentKey` changes: status, group number/name, lock state, the
history limit and `canPrevious` (they grey "previous"), the pending switch
feedback, button set and the photo on screen.
Re-posting an unchanged bar (hundreds of times a day)
is what made MIUI rate-limit the app and then hide its notifications on the lock
screen (`post_frequency` demoted every post).

`wallpaper.groupedNotification` (AppMeta, default on) is the user's switch. It
travels to the service in `state.json` as `notification`: off means no bar **and no
foreground service**, not a hidden one. The switch lives in Settings → 「Visible &
wallpaper」 and in the view page's More menu (never in the group page's menu);
either one rewrites the state and calls the `refreshNotification` channel method,
so it applies without waiting for the next bake. The About page documents that a
device may reclaim a wallpaper with no notification more eagerly, and offers to
set the wallpaper again while it is off.

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
the three-finger gesture: the app puts the group page (`/wallpaper_groups`, on
the playing group) below the view, so backing out lands on the wallpaper page.
The expanded first button only switches the button set. The screen broadcasts
(`ACTION_SCREEN_OFF`, `ACTION_SCREEN_ON`, `ACTION_USER_PRESENT`) switch the layout
family and the home/lock effect image together, and return the button set to the
keyguard's default.

Actions are broadcasts to `GroupedWallpaperActionReceiver`, so they work without
an Activity. "Next" and "previous" both first promote the queued neighbour in the
live renderer (instant, like a double tap) and only fall back to the app's command
when the renderer has nothing to show. The commands are the names of
`GroupedWallpaperCommand` (`previousArtwork`, `nextGroup`, ...), so both sides
share one vocabulary. Turning the grouped wallpaper off cancels the notification.

`state.json` carries the walk (`rewind`, `rewindCursor`) and the two baked
neighbours (`previous`, `next`). A photo the walk has never shown becomes the
newest record and resets the cursor; stepping forward through the records moves
the cursor instead, and only from the newest record does a forward step create a
new photo. The walk is capped by the usage-history limit, and the bar greys
"previous" through `canPrevious` (the `previous` slot is queued) when it is
exhausted. The `navigated` flag makes the renderer honor the new `current`:
without it, `keepDisplayedSlot()` would mistake a step back for a promotion and
keep the old frame. Every explicit step also restarts the auto-advance countdown
(`restartAutoAdvance`, replacing the pending WorkManager run), so the next
automatic change is a full interval away.

A v5 state has no baked neighbours; the first run after the update writes them
from the rewind stack and the frame cache.

### Usage history

`grouped_wallpaper_history` (schema v12) records the photos the wallpaper put on
screen, so the user can look back at them and step to the previous one.

- **Recorded when a new photo is shown**: advancing from the newest record, a
  forward step that had to pick a fresh photo, or a group switch. Stepping back
  and forth through the records adds no row: browsing is not "using" a photo
  again, and rewriting `usedAt` would reorder the very walk it is based on. A
  layout re-bake, an off switch, a lock or a failure adds no row either.
- **Per photo, per group**: the unique key is `(entryId, groupId)`, so showing the
  same photo again only moves its `usedAt` to the front, while the same photo in
  another group is a different wallpaper and keeps its own row. The row stores the
  group name/number as a snapshot, so it still reads correctly after the group was
  renamed or deleted.
- **Limit**: `wallpaper.groupedHistoryLimit` (AppMeta, 0–1000, default 200). `0`
  turns recording off and greys the notification's "previous" button, and the
  engine's `previousArtwork()` becomes a no-op. Changing the number **never
  deletes** history rows: the next recorded photo prunes the oldest beyond the
  limit, and only "clear history" removes rows. The rewind stack is trimmed at
  the same time, and clearing the history clears it too (with its cached
  frames), so "previous" never walks a private copy of records the user removed.
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

### Group lock from the notification

The bar's lock button is the group-switch lock, not a playback pause: the
wallpaper never stops rotating on its own, and there is no freeze to resume.

- **Unlocked**: the button shows an open lock and locks the group on screen
  immediately. The bar greys its group buttons and closes the icon in the same
  frame, while the receiver writes `lock_request.json` (the group id) and sends
  the `lockGroup` command. The app persists the lock in AppMeta and rewrites
  `state.json` (`switchLocked`, `switchLockedGroupId`); the headless refill
  worker adopts the request when the app was not listening, so a tap is never
  lost. The request stays until Dart clears it.
- **Locked**: the button shows a closed lock and opens
  `/wallpaper_groups/unlock`, which is the group page with the PIN sheet already
  open. Cancelling leaves the locked group on screen; unlocking with the PIN
  restores the group buttons.
- A lock the app never confirmed only shows for 30 seconds: the bar must not
  claim a protection the guard would not enforce.

Locking is the same state the group page's 「Lock the current group」 and the view
page's lock entry write, and the group page still owns the menu entry for it.

### Group switch feedback

The bar switches groups itself from the rotation carried by `state.json`
(`groups`: id, number and display name of every enabled group, refreshed on
every state write). On a tap it computes the target exactly as the engine does
(group 0 moves to the first enabled group, the rotation wraps), then shows
「Switching groups」 / 「From group 3 DCIM to group 4 Camera」 with the target
number in the badge and the group buttons greyed, and only then sends the
command. The overlay ends when a state naming the target arrives, or after 20
seconds if the bake failed; `contentKey` includes it, so the bar re-posts once
when it starts and once when it ends.

### Photo switch feedback

A previous/next photo step starts the same kind of overlay, but only when it has
to wait: the renderer promotes the queued neighbour instantly, and only a step
that could not promote (no engine, or the neighbour is still baking) reaches the
bar. The title then reads 「Switching to previous」 / 「Switching to next」, the
subtitle keeps naming the photo on screen, and the photo buttons are greyed.
The wait ends when a state shows a different `(slot, entry)` than the one the tap
left (a re-bake can keep the slot id), or after 20 seconds, so a failed bake
returns the bar to the photo that is really drawing. The rules live in the pure
`GroupedPhotoSwitchPending` object, and `contentKey` includes the direction so the
bar re-posts once when the wait starts and once when it ends.

### The view page

A three-finger tap opens an immersive view of the current photo, modelled on
Muzei's artwork screen: pan and zoom, chrome visible on open and toggled by a
tap, the group number · name · count at the bottom left, and a floating control
pad instead of buttons in the bar. A wallpaper gesture has no Activity, so the
view is pushed over the playing group's page, itself over the app's home page:
back walks view → group page → home instead of closing the app, and the group
page starts on the group being played. Opened from the group page, 「Open
wallpaper groups」 pops back to it.

The pad is a 3×3 box whose rows carry 3, 2 and 1 controls, left-aligned so the
silhouette reads as a top-left bracket:

| Row | Controls |
|---|---|
| Top (3) | previous photo, next photo, menu |
| Middle (2) | group **+1** (up), group **−1** (down) |
| Bottom (1) | delete the photo on screen |

It **floats and is draggable**: the whole staircase is the drag handle, the place
is clamped inside the safe area, stored as a fraction of the free space (so a
rotation keeps it within thumb reach) and written to AppMeta only when a drag
ends. The default anchor is the left edge a little below the middle, reachable on
a phone held in one hand. Dragging updates a `ValueNotifier` that only the pad
listens to, so it never rebuilds the photo or re-reads the wallpaper state; the
photo and the pad each sit behind a `RepaintBoundary`. The pad fades out with
the rest of the chrome, and its empty top-right corner stays transparent to the
photo's own tap.

A home photo step first asks the renderer to **promote the queued neighbour**,
which is the texture swap a wallpaper double tap makes, so the frame and the page
change at once; only a step it cannot promote (no live engine, the neighbour
still baking, or `frameRetention` keeping the frame on screen only) bakes, and
only then does the title say what it is doing and every step control grey out.
Promoting restarts the auto-advance countdown and refills the freed slot in the
background, exactly like the bar's photo buttons. The lock decoy has no queue by
design, so its steps always bake.

The group steps raise and lower the group number over the **enabled** rotation
(1 ↔ n, wrapping) and never enter group 0: with no group playing they are greyed
instead of starting the rotation from "nothing is playing". They are also greyed
while the group switch is locked, when only one group is enabled, and while a
step is in flight. A group change always bakes, so it is the one case that
always shows 「Switching groups」 with the target's number and name.

The page below the view is the `/wallpaper_groups` route itself — the page is a
navigation destination of its own, so it needs no shared shell. The
notification's body opens the same view, so both entry points land identically.

The home/lock switch is always listed: for a split group it switches which
surface the page describes, and for a group without a split it is greyed with
「This group has no lock screen setup」 instead of disappearing. Its previous/next
controls act on the decoy and are enabled as soon as the group has a lock range,
so the first step bakes the frame the page was never able to show before.

The menu is the group page's menu without the draft: open the groups, the
gallery, the whole group, share, usage history, auto-advance, effects, gestures,
the home/lock switch, the notification switch, **turn off grouped wallpaper** and
the **group lock**, plus About. Effects bind to the group aggregate rather than
the page's range controller, because effects are written straight through and
never wait for "save changes". The gallery range switch is deliberately absent:
this page is about the wallpaper, and the range switch lives where the range is
managed.

**Delete** is the pad's bottom button and the viewer's own delete action
(recycling bin, confirmations, progress report, source refresh), with a policy
that only tells the page when it succeeded: the wallpaper then shows the next
photo, which is a promotion on the home surface. A cancelled confirmation or a
failed delete leaves the frame alone. When the photo was the group's last, the
engine keeps it (the empty-group rule) and the page explains why nothing moved.
Stacks are left to the gallery viewer, which hosts the multi-page conductor the
delete needs.

The lock entry is the same group switch lock as the group page's and the bar's:
locking is direct and asks for nothing, unlocking asks for the group password,
and the group steps grey out as soon as the lock is set.

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
status). Outcomes are recorded instead of thrown: a missing photo or a failed
bake ends in the grey placeholder, while a turned-off feature keeps the frame it
stopped on. A locked range is a normal rotation: the lock guards editing and
browsing, not the photos. A failed *prefetch* keeps the frame and the queue.

**An empty group does nothing on screen.** A group whose range matches no photo
(no image at all, or restrictions that match none) records the new group and its
`count: 0`, but keeps every slot, the current frame and the decoy exactly as they
were: no `clearSlots`, no reload to the placeholder. The wallpaper is a surface
people see without opening the app, and a grey placeholder would look like the
feature broke and would draw attention to what is being hidden; keeping the last
picture is less disruptive and never reveals another group's content. The app
explains the no-op once per empty group (the notice is deduped until a successful
bake ends the episode); the notification and the page still describe the empty
group the user selected. The same paragraph is in the About page. A split whose
lock range is empty keeps its previous decoy for the same reason; only a split
that has never baked a decoy has nothing to keep, and that first bake is the one
case where the native placeholder is unavoidable.

The slot the renderer is actually drawing is not in `state.json`: a promotion
from a tap or the bar moves it before Dart writes. The app asks the live renderer
(`GroupedWallpaperRenderBus.displayedSlot()`), so the three-finger view and the
bar describe the frame on screen immediately, without waiting for the reload that
would rewrite the state. The renderer's `locked` status is legacy: an upgraded
install can still read it, and it navigates exactly like `ready`.

The service asks the app for a frame when it starts and when the app attaches, so
the wallpaper gets its first photo without a background worker; if the app is not
running, the renderer keeps its placeholder until the app is opened. The engine
is attached at startup (`main_common`), and the page re-probes `isActive` when it
opens or resumes.

### Auto-advance

Each group also owns its interval (`wallpaper_groups.interval`, seconds; `0` is
off, the default). The **option list** is shared with the Muzei wallpaper and
lives in `features/wallpaper_auto_advance/`: the built-ins and the reset target
come from `assets/wallpaper_intervals.json`, the live `defaults` + `customs`
lists are stored in AppMeta (`wallpaper.autoAdvanceIntervals`), and both
auto-advance pages manage them in place. Only the list is shared: every group and
the Muzei wallpaper persist their own selection.

- A long press on any option except Off enters multi-select deletion. Built-in
  and custom options are both deletable; Off is pinned because it is the off
  switch. Deleting resets only the groups and the Muzei wallpaper currently using
  a deleted value; it falls back to the JSON reset target, `0` (off).
- The auto-advance page's overflow menu (shared with the Muzei page) holds the
  list actions plus About:
  - 「Add default intervals」 is additive: it restores only the shipped built-ins
    that are missing (including ones deleted by hand) and changes no selection.
  - 「Clear all intervals」 removes every option except Off but changes no
    selection; Off always stays so auto-advance can still be turned off.
  - 「Reset all to default」 is the factory reset: the shipped list comes back,
    custom options are dropped, and every group plus the Muzei wallpaper returns
    to off. It is the only action that resets every selection.
- A custom value must be `3 seconds..30 days`. There is no default option in
  Dart beyond those bounds and off; changing the shipped list is a JSON edit.
  The add sheet has four digits-only boxes (days, hours, minutes, seconds, each
  0–1000), starts from the current value or 10 minutes, and says that 3 seconds
  is for testing only and that daily use should pick at least 15 minutes (1–6
  hours is typical), because short intervals wake the device often, drain the
  battery, and Android may delay them anyway. The full explanation, including the
  three list actions, is the About page behind the overflow menu.
- Adding a value that is a shipped built-in but currently missing restores it as
  a built-in, not as a custom option.

The interval and ordering are edited from the
group page's More → 「Auto-advance」, the effects page's row, or the view page's
More; all three write immediately like effects and do not bump `updatedAt`: the
contract only affects future picks, so the frame on screen is never re-baked just
because the interval changed. An explicit previous/next step restarts the
countdown (`restartAutoAdvance`, replacing the pending run) instead of keeping
the old one. The interval itself is a forward step through the usage records, so
a wallpaper left on a photo the user stepped back to returns through the records
first and only creates a new photo at the newest one.

Scheduling reuses the shared native WorkManager chain
(`LiveWallpaperRefillScheduler`, per target) through the grouped channel's
`scheduleAutoAdvance`; a finished interval run reschedules itself. The engine
applies the interval on every non-advance run and when the page edits it, and
schedules **nothing** while the wallpaper is turned off or on group 0, so it does
not wake up for a frame it would refuse to show. The native scheduler clamps the
value to `0` or `3 seconds..30 days`, so a corrupt saved value can neither loop
back-to-back nor schedule work in the far future. The interval and ordering are
group-level: the Muzei wallpaper keeps its own pair.

## Turning it on and off

`groupedDisabled` (AppMeta, `wallpaper.groupedDisabled`) is the explicit off
switch, and it is deliberately separate from the `current` flag: turning the
feature off keeps the group that was playing, so turning it back on returns to the
same content, and the flag survives a reboot, where the service starting again
would otherwise look like a fresh activation.

- **Set this group as wallpaper** (a real group) makes it current, turns the
  feature on and prepares the frame. The system chooser is only opened the first
  time, when the grouped service is not the system wallpaper yet.
- **Turn off grouped wallpaper** (group 0) sets the flag and keeps the last
  frame on screen: nothing follows the group any more. Disabling never changes
  the wallpaper the system is already showing.
- **Deleting or disabling the group that was playing** keeps its last frame and
  turns the feature off; it never switches to another group.
- **Activation with no group current** (the service starting while nothing is
  selected and the feature was not turned off) adopts the first enabled group
  instead of leaving the current flag unset. If that group matches no photo the
  empty-group rule applies: the prior frame is kept, and only a first activation
  with no frame at all can show the placeholder.

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
not `disabled`), the component is not ours, no *other* live wallpaper is bound,
and no static wallpaper file exists. That last pair is what keeps the
notice from nagging a user who picked another wallpaper, and the OEM's fallback
is distinguishable because after a reset the system keeps no wallpaper file.

The headless path is shared with Muzei instead: `features/live_wallpaper_refill/`
owns the `vm:entry-point` isolate, the warm engine and the WorkManager chain, and
dispatches by target (`muzei` / `grouped`) to
`entry/background_refill.dart`. The grouped run attaches the engine and either
prepares a frame or advances, so a tap or an interval still applies when no page
is mounted. Files, renderers and intervals stay per wallpaper.

While a grouped service is drawing, it calls `LiveWallpaperRefillEngine.holdWarm`
so the engine stays warm for five minutes instead of the 60 s burst window: a tap
with the app closed then skips the several seconds of engine and service startup.
The screen going off releases it at once (`releaseIfIdle`), and
`KEEP_WARM_ENABLED` in that engine is the one-line switch to turn it off.

Both sides decide from one predicate: `GroupedWallpaperAppBridge.canServeRequests`
requires a messenger *and* an attached Dart handler, and the background engine
registers its handler with `servesSyncRequests = false` because nothing can reach
it. Without that, the service refused a request as "no app" while the worker
skipped the run as "the page is listening", and the tap landed in the gap.

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
  range — its condition pool — whose id is *derived* (`wallpaperGroupRangeId`),
  never stored. Home and lock are projections of it; the lock's projected id
  (`wallpaperGroupLockRangeId`) is derived too. Deleting a group deletes the pool,
  its rules and applied targets in the same transaction.

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
and deletes it. A pinned condition joins the pool **unmarked**, so it changes
nothing until Home, Lock or both are marked on the group page; pinning a base
replaces the pool's base but keeps the marks it already had, because activating
or deactivating a surface's base would silently change a privacy range. Older
builds materialized that catalogue into every group; it is pruned on every start
(not only on a defaults bump), so a restored backup cannot bring it back.

The bundle also ships four **shared orientation restrictions** — landscape,
portrait, not landscape and not portrait — and every group gets them, including
groups that already exist on an upgrade and groups created afterwards. They are
demonstrations that make an empty group easy to produce while testing. Home marks
`notPortrait` and lock marks `portrait`; the two unmarked conditions stay in the
pool so the page can switch them on. The base is marked for both surfaces and
`lockRangeSeeded` is set, so enabling the split later uses these prepared lock
conditions instead of copying the home marks; `separateLockRange` itself is left
alone. The ids are `<groupId>.rule.default.<key>`, which is also what keeps the
prune pass from deleting the unmarked pair.

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
with that group (or flips the interval from the anchor, like any other grid). The
page has **two independent multi-select states**: a group selection and a
condition selection. They share one grid and one `Selection`, so the gesture layer
narrows the selectable rows to the scope already in play
(`wallpaper_page_selection.dart`, `FilterGridPage.sameSelectionScope`); a range
can never cross from the conditions into the group cards above them, and the app
bar only offers that scope's actions. Group 0 is never selectable. Deleting the
selected groups keeps at least one group and stays a draft until it is saved;
deleting the viewed group moves the page to the first remaining one.

## Browsing scopes

The gallery range and a group range are independent data sets, and both constrain
browsing. The group page publishes the range of the group it shows through
`VisibleRangeGate`, so the media set, albums, search and every other browsing
surface see the gallery range **and** the group range — exactly the photos the
wallpaper may use. The published range is the **lamped surface's projection**, not
the pool: the other surface's marks never narrow browsing. The intersection is the
default on purpose: a user may have
restricted the gallery for privacy and still hand the phone over to show the
wallpaper, so the page must not widen what the gallery hides. It is also the way
to see which photos the configured groups actually contain, so it does not depend
on the live wallpaper running or on which group is playing: only on the group the
page has selected.

The scope is app-wide, like the gallery range, and lives until the user selects
group 0, closes the page, or the process dies. A destination switch
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

In the chips and five-column switcher styles the switcher is a `headerBuilder`
sliver between the app bar and the sections, so it shifts the layout space every
selection hit test resolves against. `FilterGridPage` measures it and
`GridSelectionGestureDetector` subtracts it, which is what makes a long press
select the tile under the finger instead of the row above.

Locking a group (`group_lock_rules.dart`, persisted in AppMeta) pins the
switcher to group 0 and the locked group, disables edits to the locked group's
range, group management and pinning into groups, and makes the engine write
`switchLocked` (and the locked group's id) into `state.json` so the notification
greys its group buttons and shows the closed lock. The notification's lock button
is the same state. Locking does not prevent closing the page: that only removes
the browsing scope, while the lock and its group survive a restart until the
password unlocks them.


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
