# Navigation drawer pages — testing

## 1. Gates before a commit

```sh
./flutterw analyze
./flutterw test test/features/nav_drawer test/features/grouped_wallpaper
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-nav-drawer-rules.ps1
./flutterw test
```

## 2. Host tests

| File | Covers |
| --- | --- |
| `test/features/nav_drawer/drawer_page_routes_test.dart` | `DRW-1` … `DRW-4` |
| `test/features/nav_drawer/drawer_page_seed_test.dart` | `DRW-5` … `DRW-8` |
| `test/features/grouped_wallpaper/grouped_wallpaper_nav_test.dart` | `NAV-3` (the shared/separate opener) |

The seed tests drive the legacy settings store with the in-memory
`SharedPreferences` from `test/common.dart`; `setUpServices` clears it, so the
one-time marker starts unset in each test. `useTvLayout` is passed to the seed
instead of read from the device, because `device.isTelevision` has no value on
the host.

## 3. Device checks

- **DRW-M1 — Drawer entries and order.** Settings › Navigation › Drawer › Pages:
  the visible range is on, Muzei Wallpaper and Wallpaper groups are off. Turn
  the two off pages on, reorder them, leave the editor, and check the drawer
  matches. Turn every page off: the drawer shows no empty section divider.
- **DRW-M2 — Upgrade backfill.** On a build that predates this change, save a
  drawer page list (open the editor and leave it). Install the new build: the
  drawer still shows the visible range before Explorer. Remove it in the
  editor, restart the app, and it stays removed.
- **DRW-M3 — Picking.** Open the wallpaper picker from the grouped-wallpaper
  page: the drawer shows no visible-range, Muzei or wallpaper-groups entry.
- **DRW-M4 — Wallpaper groups entry.** With a separate bottom-bar entry, the
  drawer's Wallpaper groups entry opens the group page and back returns to
  where the user was. In the shared mode it opens the single range entry on the
  wallpaper page; pressing it again never stacks a second copy. This is the
  device half of `NAV-3`.

On Windows, database-backed tests need a full native sqlite3; see `AGENTS.md`
(`AVES_SQLITE3_DLL`).
