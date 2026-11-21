# 0002 — The previous-wallpaper flash belongs to the system, not the app

Date: 2026-11-21

## Context

On returning to the home screen, the device can briefly draw the wallpaper that
was set before the grouped one (in the report, the official Muzei wallpaper)
before the grouped wallpaper appears. The app does not reset its wallpaper on
resume: it only probes `isActive` and `restoreOffer`, and never calls the chooser
by itself.

## Decision

Treat the flash as a system transition. Android keeps the replaced wallpaper as
its previous one and may draw it while the new live-wallpaper engine starts. The
app documents the mechanism (`recurrences.md` R7) and does not claim a fix.

A mitigation is still allowed if it does not change what the feature promises:
keeping the engine alive longer, or writing a matching static snapshot as the
fallback, is judged on its own in a later record. It must not silently rebind the
component or change the wallpaper the user picked.

## Why not "fix" it in the app

- `SET_WALLPAPER_COMPONENT` is `signature|privileged`; a normal install cannot
  rebind silently.
- The previous-wallpaper frame is owned by `WallpaperManagerService`; an app
  cannot remove it.
- The same flash exists for any two live wallpapers, so it is not specific to
  this feature.

## Verification

`rules.md` `SWITCH-1` is `M`. The device checklist in `testing.md` records the
engine's `destroy`/`create` pair and which package the previous frame belongs to.
