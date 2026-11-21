# 0004 — A step that baked reads the baked frame

Date: 2026-11-21

## Context

A view-page step first tries to promote the queued neighbour. When that fails
(the neighbour's texture is not uploaded yet, the wallpaper is turned off, or the
history has no neighbour), the app bakes instead: `nextArtwork` / `previousArtwork`
writes a new `state.json` and asks the renderer to reload it.

The reload is asynchronous. Reading the renderer's drawn slot right after the
bake describes the frame the step just replaced. When that frame's file has
already been evicted by the cache, `photoPath` is null and the page shows "the
grouped wallpaper has no photo to show yet" while the desktop bakes the new one.
This is the second form of the display drift (R1c).

## Decision

The view page picks the source by the path it took:

- **Promotion** — `promotePhoto` answered true. Read the renderer snapshot; it
  draws the promoted slot.
- **Bake** — `nextArtwork`, `previousArtwork`, a lock step or a group switch.
  Read the baked current (`readBakedFrame`), because the step just wrote it and
  the renderer will catch up later.

The two are not interchangeable. The snapshot answers "what is on screen now";
the baked frame answers "what did the step produce". A step produces the latter,
and the user pressed the control to see it.

`readDisplayedFrame` still covers the cases where the renderer names a slot whose
file was evicted: it falls back to the baked current instead of the placeholder.

## Alternatives rejected

- **Wait for the renderer to adopt the state.** The bake takes hundreds of
  milliseconds to seconds; the page would look unresponsive, and a slow reload
  would leave it stuck.
- **Always read the baked current.** A promotion is exactly the case where the
  renderer is ahead of `state.json`; reading the baked current would rewind the
  page to the photo the promotion left.
- **Make the native reload synchronous.** It runs on the loader thread and
  decodes frames; blocking the channel would stall the view page.

## Consequences

- `WallpaperEngineConnection.readBakedFrame` is the page's post-bake read.
- The promotion path keeps `readDisplayedFrame`.
- `rules.md` DISP-8/DISP-9 and `recurrences.md` R1c hold the behaviour.
