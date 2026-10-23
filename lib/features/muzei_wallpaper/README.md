# Muzei wallpaper

This feature is a fork-only port of [Muzei](https://github.com/muzei/muzei)
(Apache-2.0) to Aves. It is not an independent design; the product behaviour and
the Android wallpaper lifecycle intentionally follow Muzei.

The development reference was the sibling `muzei` checkout.

## Ported from Muzei

- `main/src/main/java/com/google/android/apps/muzei/MuzeiWallpaperService.kt`
  - WallpaperService/Engine lifecycle, `directBootAware`, touch/offset
    notifications.
- `main/src/main/java/com/google/android/apps/muzei/render/MuzeiBlurRenderer.kt`
  - Blur, dim and greyscale values; sharp/effect crossfade; focus behaviour.
- `main/src/main/java/com/google/android/apps/muzei/render/GLPictureSet.kt`
  - Cover-fit matrices, desktop offset and zoom.
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
  owned by `WallpaperStateStore`.
