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
