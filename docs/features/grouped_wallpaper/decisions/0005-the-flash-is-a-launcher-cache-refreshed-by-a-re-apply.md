# 0005 — The flash is a launcher cache, refreshed by a re-apply

Date: 2026-11-21

## Context

Record [0002](0002-the-previous-wallpaper-flash-is-the-system.md) called the
previous-wallpaper flash a system transition the app cannot remove. A device
capture on 2026-11-21 narrows it down:

- During the swipe-home animation the launcher draws the wallpaper from before
  the grouped one, every time, for the whole capture.
- The renderer's texture map holds only the three current slots
  (`skip=[0, 1, 2] decode=[]`); the flashed photo is not one of them, and it is
  not in the frame cache either. The renderer cannot be drawing it.
- `surface.created` is followed by `displayed=<current>` within about 5 ms, so
  the grouped surface is current as soon as the launcher composes it.
- An activity switch (`am start` of the home intent) does not flash; only the
  launcher's swipe animation does.
- After the user set the current group as wallpaper through the system chooser
  (bind source `SET_LIVE`), the flash was gone and stayed gone across later
  photo changes.
- A package replace silently rebinds the component (bind source
  `PACKAGE_UPDATE_FINISHED`); the flash returns until a chooser set refreshes
  the launcher.

## Decision

Treat the flash as the launcher's cached transition frame, not as the grouped
renderer and not as the system's previous-wallpaper buffer. The cache is
refreshed by a normal live-wallpaper set (`SET_LIVE`), not by a silent rebind.

The app therefore:

- documents the workaround — set the current group as wallpaper once after an
  update — as a known issue;
- treats the package replace as the trigger, not the photo change: later photo
  changes follow the live wallpaper once the cache has been refreshed;
- does not write a static wallpaper as a fallback. AOSP's `setBitmap`/`setStream`
  replaces the live component with `ImageWallpaper`, which would unbind the
  feature.

The next step is a one-tap re-apply after a package replace, because the app
cannot bind the component itself: `SET_WALLPAPER_COMPONENT` is
`signature|privileged` and is not granted to the custom build.

## Consequences

- `recurrences.md` R7b records the trigger and the falsifier.
- The Advanced > Known Issues page carries the user-facing workaround.
- A "previous-wallpaper flash" that survives a chooser set, or one that appears
  without a silent rebind, contradicts this record and reopens the analysis.
