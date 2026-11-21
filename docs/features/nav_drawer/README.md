# Navigation drawer pages

The drawer's page entries are one ordered, editable list. The fork's own pages —
the visible range, the Muzei Wallpaper page and the wallpaper groups — are options
of that list, not fixed tiles.

Status: **in progress**. Implemented on `avest-dev`; nothing is released yet.

## Scope

In scope:

- which page entries the drawer shows, and in which order;
- the fork pages as editor options;
- their defaults and the one-time backfill of the legacy visible-range tile;
- which entries a photo pick leaves out;
- the drawer entry that opens the wallpaper groups.

Out of scope:

- the bottom bar: it has its own editor and derives the range/wallpaper entries;
- the drawer's type and album bookmarks;
- the TV rail's layout (it reads the same list and only shares the wallpaper
  entry's opener);
- the pages themselves.

## Version facts

| Fact | Value |
| --- | --- |
| Stored list | `SettingKeys.drawerPageBookmarksKey` (`drawer_page_bookmarks`) |
| Fork routes | `/visible_range`, `/muzei_wallpaper`, `/wallpaper_groups` |
| One-time marker | `SharedPreferences` key `nav_drawer.fork_pages_initialized` |
| Editor | Settings › Navigation › Drawer › Pages |
| Defaults | visible range on; Muzei Wallpaper and wallpaper groups off |
| Legacy slot | before Explorer, else last |

## Reading order

1. `spec.md` — what the drawer list must do, as acceptance criteria.
2. `rules.md` — the case register; every row names the test that holds it.
3. `decisions/` — why the list is the single source and why the backfill exists.
4. `testing.md` — the gates and the device checks.
5. `tasks.md` — what is still open.

## Code map

| Layer | Path |
| --- | --- |
| Routes and options | `lib/features/nav_drawer/model/drawer_page_routes.dart` |
| One-time backfill | `lib/features/nav_drawer/services/drawer_page_seed.dart` |
| Marker key | `lib/features/nav_drawer/model/drawer_page_keys.dart` |
| Defaults | `lib/model/settings/defaults.dart` |
| Drawer | `lib/widgets/navigation/drawer/app_drawer.dart` |
| Editor | `lib/widgets/settings/navigation/drawer_editor_page.dart` |
| Wallpaper-groups opener | `lib/features/grouped_wallpaper/view/grouped_wallpaper_open.dart` |
| Startup | `lib/widgets/aves_app.dart` (`_setup`) |
| Tests | `test/features/nav_drawer/`, `test/features/grouped_wallpaper/grouped_wallpaper_nav_test.dart` |

The slice owns the decisions; upstream trees only gain the minimum wiring: the
default list, one line in the drawer editor, the drawer's entry builder, the TV
rail's opener and the startup seed.

## Privacy note

Every route in this directory is a stand-in. User-facing names come from the ARB
catalog; no local path appears here.
