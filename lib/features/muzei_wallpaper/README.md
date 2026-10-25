# Muzei wallpaper

This feature is a fork-only port of [Muzei](https://github.com/muzei/muzei)
(Apache-2.0), created by Ian Lake, to Aves. It is not an independent design; the
product behaviour and the Android wallpaper lifecycle intentionally follow
Muzei.

The development reference was the sibling `muzei` checkout.

## Ported from Muzei

- `main/src/main/java/com/google/android/apps/muzei/MuzeiWallpaperService.kt`
  - WallpaperService/Engine lifecycle, `directBootAware`, touch/offset
    notifications.
- `main/src/main/java/com/google/android/apps/muzei/wallpaper/LockscreenObserver.kt`
  - Home/lock surface detection from the screen broadcasts and the keyguard.
- `main/src/main/java/com/google/android/apps/muzei/render/MuzeiBlurRenderer.kt`
  - Blur, dim and greyscale values; sharp/effect crossfade; focus behaviour.
  - 750 ms artwork crossfade, 500 ms effect fade, queueing a frame while fading.
- `main/src/main/java/com/google/android/apps/muzei/render/GLPictureSet.kt`
  - Cover-fit crop, desktop offset and zoom, ported as `WallpaperViewport`.
- Muzei's tap actions and auto-advance settings
  (`temporarily disable effects`, `next artwork`, `view artwork`, intervals and
  ordering).
- `net.rbgrn.android.glwallpaperservice` (Muzei's vendored copy of the AOSP GL
  wallpaper service), kept under
  `android/app/src/main/java/net/rbgrn/android/glwallpaperservice/`.

The vendored Java files and the Kotlin service/renderer retain their
Apache-2.0 headers. See the repository root `LICENSE` for Aves's own license.

## Aves-specific differences

- Dart bakes `sharp.png`, `effects_home.png` and `effects_lock.png`; the native
  renderer only owns textures, crossfades, focus, offset/zoom and gestures.
- Source queries go through Aves's Drift database instead of Muzei's content
  providers.
- The Dart/native contract is `state.json` / `runtime.json` plus slot PNGs,
  owned by `WallpaperStateStore`. A wallpaper tap that advances the artwork
  writes the new slot to `runtime.json`; while the generations match, the
  renderer (and the next Dart adoption) treat the runtime as the current slot,
  so an advance survives without Flutter running.
- Flutter normally bakes one artwork ahead, so a tap burst outruns the refill. The
  two-ahead option (Meta Settings → Advanced, on by default) keeps a second
  spare so the first two taps are instant; after that the renderer still buffers
  taps (`AdvanceRequestQueue`) and replays them one per prefetch instead of
  dropping them, keeping Muzei's "every double tap advances" behaviour. While the
  app process is alive it is also notified over the channel (`advanceRequested`)
  so the refill starts immediately rather than on the next page resume.
- When no app engine is attached, the notification enqueues
  `WallpaperRefillWorker` instead: it boots a short-lived Flutter engine, runs
  `entry/refill_entry.dart` (adopt the promoted slot, bake the next one) and
  destroys the engine. A WorkManager chain, not a long-lived process, so taps
  keep advancing after the app is closed or killed. The tap run is a plain job,
  deliberately not expedited: on Android 12+ expedited work becomes a foreground
  service, which demands `getForegroundInfo()` and a notification for a
  two-second bake.
- A tap that finds no prefetched slot also requests the refill (deduplicated
  with `KEEP`). Otherwise the promotion never happens, so nothing would ever ask
  for the missing slot and the buffered taps would expire.
- Android does not run queued work for a force-stopped app, so a tap after an
  explicit force-stop still uses the one prefetched slot; a normal process death
  or swiping the app away is covered, and the chain resumes on the next launch.
- Auto-advance is a chain of one-time WorkManager runs driven by the interval
  preference (15 minutes to 3 days, or off), because the page may be gone for
  hours. A run advances the state in Dart, then asks the running app to refresh
  its preview and schedules the next interval. The chain is cancelled while the
  wallpaper is not in use, so replacing it with another app stops the background
  bakes instead of leaving them running.
- Ordering mirrors Muzei's Auto Advance screen: always in order, new photos in
  order then random (the default), and always random. "New" is an entry id above
  the highest one shown (`newestEntryId` in `state.json`, Muzei's
  `maxLoadedArtworkId`); when nothing is new the pick falls back to random,
  which rejects the current artwork and the recently shown ones (up to 50).
  One deliberate difference: Muzei starts its marker at zero and walks the whole
  feed first, which for a library of tens of thousands of photos would take
  years, so the marker is seeded to the newest existing photo when the source is
  set — "new" means added after the wallpaper was set up. The Wi-Fi-only option
  is absent because the source is local.
- The foreground page and the background run can overlap, so both mutate the
  store under a file lock (`WallpaperStateStore.runExclusive`) and re-read
  `state.json` before choosing a slot. The winner is the last committed state,
  and the loser adopts it instead of baking the same slot twice.

## Foreground page

The page is reached from the drawer, so it keeps a back arrow at the top and
drops Muzei's bottom tab bar: sources, effects and gestures live in the one
overflow menu, which also floats on their own pages so switching never needs a
trip back to the artwork. The overlay is a single row, Muzei's visual signature:
the title line, "touch to view", the next button and the overflow. A tap toggles
the whole overlay (back arrow included) so the picture can be looked at alone
and a long press opens the immersive artwork view. The double-tap and
three-finger bindings belong to the desktop wallpaper only: this page is a
viewer, and a stray in-app tap must not change the wallpaper behind it. The
artwork is laid out at its cover size and panned inside an `InteractiveViewer`,
so 1x can already reach the parts the wallpaper crops away; the view recenters
when the artwork or the window changes, and nothing is persisted, because the
wallpaper keeps showing the whole frame.

The effects page is its own preview. Muzei's live feedback comes from the system
wallpaper preview, where its effects screen floats over the running engine; this
port bakes ahead of time, so a rebake takes hundreds of milliseconds and can
never follow a slider. The page therefore applies the same blur, greyscale and
dim math on the GPU (`ImageFiltered`, `ColorFiltered`, `dimAlpha`) while a
slider moves, and the debounced bake still updates the real wallpaper. Its two
presets are "reset to zero" and "Muzei defaults" (250/128/0). Our own defaults
are 0/0/0, deliberately unlike Muzei and not an oversight: the wallpaper exists
to show the photo, and every effect is opt-in.

The title line defaults to the artwork's file name rather than Muzei's source
label, which never explained itself; the source wording is one setting away.
The title and "touch to view" share their actions: a tap opens the Aves viewer,
a long press hands the artwork to another app. That viewer sits behind a
wallpaper-specific delete policy: in "My photos" mode a successful delete
advances the queue; in "Single picture" mode the original and the private copy
are distinguished, so deleting the original says the copy keeps the wallpaper
working, while deleting the copy warns that the wallpaper stops. Only that
viewer confirms; a delete from the normal gallery is unchanged. When the queue
is empty the page shows the most recent artwork whose original file still
exists, baked in memory; it never writes a slot, so history cannot rewind the
wallpaper. With no history either, the page shows the ordinary "no artwork"
hint: the feature ships no bundled image, so it adds nothing to the APK or to
storage, and an empty source renders the renderer's neutral clear color instead
of a development placeholder. The wallpaper only ever reads photos; its own
writes stay inside the app's private directory (`state.json`, `runtime.json`,
the slot PNGs).

Sources open Aves' own album and collection pages inside a picker sandbox. The
pencil opens the source on the album list when it has no filter set yet (and
always in "Single picture" mode, where finding a photo by album is faster); a
configured set opens on its media set. The picker is a route that hosts its own
navigator, so tapping an album opens that album's normal media set, the drawer
and bottom bar navigate as usual (minus the live-wallpaper page, the bin, the
home link and the video destination, which a photo pick cannot use), and none of
that navigation can drop the source page (or the wallpaper controller)
underneath. The bottom bar's photo destination stays inside the pick: it reopens
the picker's own set instead of the library's. A source can be any filter set,
not just an album: filters are added through the search sheet or the album grid,
and chips are removed one by one or with the bar's clear button. Picking an album
replaces the album condition and keeps every other one, and a long press still
unions albums with an `OR` filter, as the collection's own filters are ANDed.
The picker can also rename, delete, hide, pin or set the cover of its albums,
because it is the app's real page and the user may need to organize the library
while browsing. The My photos chips are always shown on the Sources page,
whatever source is active, and can be collapsed; the reset action only clears
those filters and never switches the active source. It confirms first (with
"don't ask again", re-enabled from Settings → Advanced), because it drops the
whole set.

The two sources are independent. A single picture never inherits the My photos
filters, and editing either source only persists its own data: editing the
inactive one does not rebake, advance or touch the baked slots. The revision
that decides a rebake therefore covers the active kind only.

The photo restriction is invisible: the lens carries the image MIME filter, the
filter bar hides it, and both the chip gestures and "clear filters" preserve it,
so the picker only ever lists photos while the pages it opens behave normally and
the "show videos" setting is untouched. Video filters the search sheet adds are
dropped silently.

A tap on a photo always opens the normal viewer, in both modes. In "My photos"
mode the picker's button says "Use these filters" and confirms the set (disabled
while the set is empty). In "Single picture" mode a long press marks a photo on
the grid and the button becomes "Use this photo"; the same button also floats in
the viewer, where it confirms the photo on screen and returns to Sources at once.
The viewer opened from the picker keeps editing and deleting, so the choice can
be inspected and cleaned up without leaving the pick. The app then copies the
bytes under `<root>/source/single.*` (one copy at a time, with 64 MiB of headroom
so a copy cannot starve the bake) and stores the copy's metadata in the scope, so
deleting the original photo leaves the wallpaper working. A read or write
failure, or a full volume, cancels the change and keeps the previous source. The
copy and its snapshot outlive source changes: switching to "My photos" and back
returns the same artwork without picking it again, even when its original photo
was deleted; choosing another artwork is what replaces it.

The copy can also be deleted explicitly from the Sources page, with a warning
that says whether the original still exists. Deleting it never discards the baked
slots: the home screen keeps showing the artwork it already shows, while the
source stops producing new ones. Its entry id is kept, so if the original is
still in the library the wallpaper keeps baking from it; if it is gone too, the
source reports unavailable.

## Session restore

When Android kills a paused process, the next plain launch reopens the top-level
page the user was on: a collection with its filters, the album list, the tag
list, the map or the wallpaper page. A viewer restores to the media set under it
rather than reopening the photo. A task swiped away from recents, or an app left
with the back button, clears the snapshot, and any real intent (a share, a pick,
a shortcut) wins over it. Picker pages are never restored: their navigator is
nested and their task no longer exists.

The about dialog blurs and dims the artwork behind it, and its Muzei section is
quoted verbatim from Muzei's `about_body`, including its own version. Our app
version is deliberately not shown there: a release that only touched other
features must not read as "the wallpaper changed again".

## Trade-offs

- Effects are blurred at a quarter of the surface (as in Muzei) but stored at
  full size. Keeping the quarter-size PNG and letting the GPU upscale it would
  save one encode/decode per effect image, but the sharp PNG dominates the
  refill, and identity effects are byte-identical to it anyway; equal-sized
  PNGs also keep the "preview and desktop read the same file" contract simple.
- Prefetch depth is a user choice. Two baked artworks (the default) keep the
  first two taps instant and cost one extra slot: roughly 13 MB of PNGs on a
  1080p phone, plus a third artwork in every effect rebake. Turning the option
  off drops the spare and its files, restoring the original two-slot contract.
  Going deeper than two is not offered: each level costs another slot and another
  +50% on every effect change, while only buying one more instant tap. The
  background refill still means a tap beyond the queue waits for a bake (~2 s in
  a profile build) instead of being lost.
