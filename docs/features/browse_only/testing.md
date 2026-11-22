# Browse only — testing

## Host coverage

All tests are under `test/features/browse_only/`; the services are driven against
`test/fake/media_store_service.dart` (a fake with request counters, injected
failures, timeouts, empty pages, colliding ids and a stalled cursor).

| File | Covers |
| --- | --- |
| `services/browse_library_paging_test.dart` | the window: page size, cursor, limit, dedupe, filtered pages, stalled cursor, failure/retry, timeout, disposal, handoff race, exact multiples |
| `browse_library_test.dart` | row mapping, sort-date fallback, order, sections, hidden albums, entry cache, synthetic ids, clear |
| `model/browse_grid_items_test.dart` | months as headers plus rows, no cross-month row, full coverage |
| `model/browse_scroll_map_test.dart` | offsets, clamping, snapping, crumb fractions, empty list |
| `model/browse_drawer_entry_test.dart` | the fail-closed whitelist and the organized case |
| `browse_albums_test.dart` | the aggregate read, idempotence, hidden set, disambiguation, sorting, retry, timeout, clear race |
| `services/browse_album_loader_test.dart` | folder scoping, whole-folder read, failure/resume, notifications |
| `browse_media_grid_test.dart` | the widget: headers scroll with rows, the drag handle lands on a month |
| `view/browse_bottom_bar_test.dart` | the widget: user order, appended destination, greyed entries, view switching |

The widget tests stub `Settings` (the grid reads the tile extent) and pin the
locale.

## Device checks

These need the real MediaStore, the app shell or layout:

| Check | Steps |
| --- | --- |
| Placement | Start a first import on a large library; the browser replaces the grid and the handoff swaps back |
| Provider paging | Scroll a 30k-row library: tiles keep arriving and no row repeats or is skipped |
| Cursor keyset | Scroll past a page boundary on a device with revisions; the next page follows |
| Folder scoping | Open an album from the browser; it shows only that folder |
| Preview strip | Reach the 5000-row limit; the strip appears and "load more" continues |
| Bar and drawer | Browsing: metadata entries are greyed and do not react; after the handoff they are enabled |
| Viewer | Tap a tile near the top and near the end; the viewer opens at that photo and pages a bounded set |
| Empty and error | Revoke media permission or use an empty library; the page says what happened and offers retry |

## Debt

- `BrowsePrefs` has no host test (defaults, read fallback, the no-op guard, the
  four keys).
- `openBrowseOnlyViewer` bounds, the ±250 window and `listenToSource: false` are
  untested.
- The page chrome (title derivation, spinner, error bar, preview strip) and the
  sort menus are layout.
- The handoff wiring in `CollectionPage` (clear both singletons on `ready`) has no
  test.

`tasks.md` tracks these; they are not claimed by a rule.

## Discipline

- A window change starts in `browse_library_paging_test.dart`; the grid and album
  tests only prove the window is applied.
- The fake media store is the contract: a new page field is added there first.
- The native keyset SQL is verified on a device only; a host test cannot falsify a
  provider's selection parsing.
