# 0006 — A gesture-opened view is the root of its flow

Date: 2026-11-21

## Context

The view gesture (double tap by default; three-finger tap opens the next photo)
on the grouped wallpaper opens the view page through a cold-start intent
(`GroupedWallpaperAppBridge.requestView`). The notification body opens the same
route. A gesture has no Activity of its own, so the app has to decide what the
user returns to.

The same view is also opened from the group page's menu, where the group page is
already the page the user came from.

Previously the intent-built stack pushed the home page, then the playing group's
page, then the view. Back walked view → group page → home. That kept a back press
from closing the app, but it also meant a gesture that started on the desktop
returned to a navbar wallpaper page the user had not opened, and 「Open wallpaper
groups」 was a back rather than a push.

## Decision

The two entry points get different roots:

- **Gesture or notification** — the view is the app's root route. Back leaves to
  the desktop through the app's double-back setting (the first press warns when
  that setting is on). 「Open wallpaper groups」 pushes the playing group's page
  over the view, so a return from it lands on the photo again.
- **Group page menu** — the group page stays below the view. Back returns to it,
  and 「Open wallpaper groups」 pops.

`GroupedWallpaperViewPage.groupPageBelow` selects the behaviour, and the pure
`groupedWallpaperViewGroupNavigation` decides push versus pop.

## Alternatives rejected

- **Keep the group page below the view for a gesture.** It makes back land on a
  page the user did not open, which is the complaint that started this record.
- **Let a back from the root close the app unconditionally.** The app already
  offers a double-back-to-exit setting; the view must honour it rather than
  bypass it.
- **Push a second group page from a group-page-opened view.** That would stack
  two copies of the same destination; the existing page is already the source.

## Consequences

- `home_page.dart` no longer lists the grouped view among the overlay routes, so
  the generic root-route path builds it; the gesture-only group page push was
  removed.
- The view wraps its root form in `AvesPopScope` with the double-back handler.
- `rules.md` NAV-1/NAV-2, `spec.md` FR-9 and the slice README hold the behaviour.
