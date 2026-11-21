# 0008 — The drawer entry opens the range's wallpaper page

Date: 2026-11-21

## Context

The wallpaper groups became a drawer option. The visible range's own menu
already has an「Open wallpaper groups」action, and that action is not a plain
navigation: with a separate bottom-bar entry it opens the group page as a
destination of its own, while in the shared mode the two pages live behind the
single range entry and the action only flips that entry's sub-page.

A drawer tile that pushed `/wallpaper_groups` directly would therefore disagree
with the range's action in the shared mode, where it would open a second copy of
a page the range entry already hosts.

## Decision

The drawer, the TV rail and the visible range's menu call one opener,
`openGroupedWallpaperGroups`. Its decision is pure and tested separately:
flip the shared entry when it is on screen, open the shared entry on the
wallpaper page when it is not, and open the wallpaper page itself in a separate
mode.

## Alternatives rejected

- **Push the route from the drawer.** Duplicates the page in the shared mode and
  leaves two entries describing one page.
- **Hide the drawer option in the shared mode.** The user asked for the entry;
  routing it through the range's action makes it correct in both modes.

## Consequences

- `groupedWallpaperOpen` holds the decision, and
  `grouped_wallpaper_nav_test.dart` covers the three cases.
- The visible range's `_openWallpaperGroups` delegates to the same opener; its
  behaviour is unchanged.
- `rules.md` `NAV-3` and `spec.md` FR-11 hold the behaviour.
