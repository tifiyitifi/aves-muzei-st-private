# Grouped wallpaper — design

The mechanism, kept short. The full narrative with every past fix is
`lib/features/grouped_wallpaper/README.md`; this file holds the invariants the
rules depend on.

## Two writers, two files

| File | Owner | Holds |
| --- | --- | --- |
| `state.json` | Dart | generation, status, group, queue, slots, effects, settings snapshot |
| `runtime.json` | native renderer | generation, the slot it promoted, whether a refill is wanted |

The renderer never reads the app database. Dart never uploads a texture.
`state.json` is written by the engine after a bake; `runtime.json` is written
synchronously by the renderer the moment a promotion lands, because the app
reads it as soon as it hears about the tap.

## Slots and the queue

`GroupedWallpaperSlot.id` is a small integer, recycled from the smallest free
id. It is stable **while that slot exists**, not across generations: a bake can
reuse an id for another photo. The queue is `previous → current → next`, both
neighbours baked so a tap is a texture swap.

`current`, `previous` and `next` name slot ids. `slotById` is the only way to
resolve one.

## The generation invariant

Every `state.json` write bumps `generation`. The renderer records the generation
it adopted. A promotion keeps the renderer's generation and writes the target to
`runtime.json`; the background refill then bakes a newer state.

Two races follow from this:

- **renderer behind**: the renderer still draws generation `G`, while the file
  already holds `G+1`. Slot id `3` in `G` may be another photo in `G+1`.
- **renderer ahead**: the renderer kept the slot on screen while the state was
  rewritten; a reload must not rewind to the new `current` unless the step was
  deliberate (`navigated`).

`GroupedDisplay` is the pure decision for a reload: it separates the state's
intent (`desired`) from what is really drawn (`displayed`), so a temporary
fallback is reversible.

## The displayed frame is a renderer snapshot

The view page, the notification and the effects editor must describe the frame
the user sees. The renderer is the only authority: it can promote a slot without
Dart writing, and it can keep drawing a slot a reload no longer calls current.

`displayedSlot` therefore returns, from the renderer's own state:

- the drawn slot id and surface;
- the renderer's `state.generation`;
- the drawn slot's metadata (entry id, uri, title, sharp photo, effects,
  width, height, quarter turns).

The Dart side builds a `GroupedWallpaperSlot` from that snapshot and injects it
for the drawn id. It does **not** resolve the id against a newer `state.json`,
because an id is only valid in its generation. When no renderer runs, the baked
`current` is the fallback.

## Reload and retention

A reload only drops frames the new state no longer names. The slot on screen and
a frame still fading out survive whatever the state says; a slot that left the
queue or whose `(entryId, photo)` changed is dropped. The decision is
`GroupedTextureRetention`, and the surface epoch guards an EGL rebuild.

## Promotion and taps

A tap promotes `next` only when its texture is uploaded. A tap that arrives
before the upload is buffered (capacity and window in
`GroupedAdvanceRequestQueue`) and replayed after the refill, unless the wallpaper
must not move at all (turned off or group 0). A promotion is forward-only; the
app adopts `runtime.json` instead of racing its write.

## Sizing

Frames are baked for the renderer's real surface. `WallpaperManager`'s desired
size can be a square on some ROMs (`2340×2340` on MIUI), which would tell a
portrait screen that every photo already matches it. The surface is recorded by
the real engine only; a launcher change drops the measurement.

## Rebind and restore

A system update or an OEM force-stop can drop the wallpaper. The app cannot
rebind silently (`SET_WALLPAPER_COMPONENT` is `signature|privileged`), so it
offers: a one-tap notification when the app is closed, and an in-app strip when
it is open. The decision (`restoreOffer`) distinguishes a reset from a wallpaper
the user deliberately picked.

## The previous-wallpaper transition

Switching to this service replaces the previous live wallpaper. The system keeps
the replaced wallpaper as its previous one and may draw it while the new engine
starts. The app cannot remove that frame; it can only reduce engine churn. This
is a system transition, documented in `recurrences.md` R7 and `decisions/0002`.
