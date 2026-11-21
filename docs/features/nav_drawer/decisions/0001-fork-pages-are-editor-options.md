# 0001 — The fork pages are options of the one page list

Date: 2026-11-21

## Context

The drawer's page entries were part of the editable `drawer_page_bookmarks`
list, but the visible range and the Muzei Wallpaper page were injected as fixed
tiles before Explorer. They could not be removed, reordered or re-added, and the
wallpaper-groups page had no drawer entry at all.

The drawer editor already offers one ordered, reorderable list. A second
fork-owned list would have to be merged at build time, and its entries could not
be reordered across the boundary: dragging them in the editor would silently
snap back after saving.

## Decision

The fork pages are ordinary options of `drawer_page_bookmarks`:

- the drawer renders the list and nothing else;
- the editor offers the upstream options first, then the three fork routes;
- the default list carries the visible range in the slot the fixed tile had, and
  neither wallpaper page;
- the one-time backfill adds the range to a list saved before this change, and
  the editor records that the list was seen, so a later removal sticks. The
  marker lives in `SharedPreferences`, outside both settings stores, so a
  settings-engine switch cannot replay the migration.

The wallpaper-groups entry routes through the visible range's own opener
(`openGroupedWallpaperGroups`), so the shared navigation mode cannot open a
second copy of the page the range entry already hosts.

## Alternatives rejected

- **Keep the fixed tiles and add a hide toggle.** Two sources for one fact, and
  the editor could not reorder the fixed entries.
- **A separate fork list.** Merge order and reordering would disagree with what
  the editor shows.
- **Default the wallpaper pages on.** Neither was in the drawer before; showing
  them would add destinations the user never chose.
- **Always re-add the range when it is missing.** That is the bottom bar's rule,
  and it makes removal impossible.

## Consequences

- `SettingsDefaults.drawerPageBookmarks` gains the visible range.
- `lib/features/nav_drawer/` owns the routes, the picking filter and the seed;
  `spec.md` and `rules.md` hold the behaviour.
- An imported pre-change backup keeps its own list: the backfill is marker-gated
  and has already run on that install.
