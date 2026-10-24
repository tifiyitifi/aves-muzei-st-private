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
- Flutter bakes exactly one artwork ahead, so a tap burst outruns the refill.
  The renderer buffers those taps (`AdvanceRequestQueue`) and replays them one
  per prefetch instead of dropping them, keeping Muzei's "every double tap
  advances" behaviour. While the app process is alive it is also notified over
  the channel (`advanceRequested`) so the refill starts immediately rather than
  on the next page resume.
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
  its preview and schedules the next interval.
- The foreground page and the background run can overlap, so both mutate the
  store under a file lock (`WallpaperStateStore.runExclusive`) and re-read
  `state.json` before choosing a slot. The winner is the last committed state,
  and the loser adopts it instead of baking the same slot twice.

## Trade-offs

- Effects are blurred at a quarter of the surface (as in Muzei) but stored at
  full size. Keeping the quarter-size PNG and letting the GPU upscale it would
  save one encode/decode per effect image, but the sharp PNG dominates the
  refill, and identity effects are byte-identical to it anyway; equal-sized
  PNGs also keep the "preview and desktop read the same file" contract simple.
- Prefetch depth stays at one artwork. A deeper queue would make the first
  extra tap instant, but it turns `state.json` / `runtime.json` from one `next`
  slot into a queue, doubles the baked disk footprint and multiplies the
  cross-process consistency cases. Buffering the taps (plus the background
  refill) already preserves "every double tap advances"; only the wait remains.
