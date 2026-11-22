# Browse only

The library surface shown while the one-time import is still building the
database: a MediaStore-paged timeline and album grid that answers from the media
store alone, so a half-written database can never make the library look empty.

Status: **in progress**. The page, the paged window, the album list and the bar are
on `avest-dev`; nothing is released yet.

## Scope

In scope:

- the browse timeline (a bounded preview of the newest rows) and its month
  sections;
- the browse album list, read as one aggregate, and the album page's whole-folder
  read;
- the bottom bar that keeps the user's own navigation and greys what it cannot
  serve;
- the drawable navigation entries and the timeline scroller;
- the browse sort preferences, isolated from the collection's own sort.

Out of scope:

- importing, cataloguing or the handoff itself (owned by `collection_paging`);
- the notice strip and the action lock (owned by `collection_paging`);
- any action that needs catalogued metadata (it is greyed, not emulated).

## Version facts

| Fact | Value |
| --- | --- |
| Page size | 250 rows (`BrowseLibrary.pageSize`) |
| Preview limit | 5000 rows (`previewRowLimit`) |
| Page timeout | 15 s; the album-list aggregate read 3 min |
| Entry cache | 600 materialized entries, LRU |
| Viewer window | ±250 neighbours in display order |
| Preference keys | `browse_only.media_sort`, `.media_reverse`, `.album_sort`, `.album_reverse` |
| Scroller | from 4 month sections |
| Rule check | `scripts/check-browse-only-rules.ps1` |

## Reading order

1. `spec.md` — what the surface shows and how it pages.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the window, the index, the album list and the bar.
4. `decisions/` — why a separate surface, why a bounded preview, why the bar is
   the user's, and why the preview counts what the grid shows.
5. `testing.md` — the fakes, the widget tests and the device checks.
6. `tasks.md` — known gaps: the handoff wiring and the viewer's detached lens.

## Code map

| Layer | Path |
| --- | --- |
| Page and views | `lib/features/browse_only/view/` |
| Window | `lib/features/browse_only/services/browse_library.dart` |
| Album list and loader | `lib/features/browse_only/services/browse_albums.dart`, `browse_album_loader.dart` |
| Preferences | `lib/features/browse_only/services/browse_prefs.dart` |
| Log channel | `lib/features/browse_only/log.dart` |
| Models | `lib/features/browse_only/model/` |
| Viewer lens | `lib/features/browse_only/model/viewer_lens.dart` |
| Media store contract | `lib/services/media/media_store_service.dart`, `android/app/src/main/kotlin/deckers/thibault/aves/model/provider/BrowseMediaStore.kt` |
| Wiring | `lib/widgets/collection/collection_page.dart`, `lib/widgets/filter_grids/albums_page.dart`, `lib/widgets/navigation/drawer/app_drawer.dart` |
| Tests | `test/features/browse_only/` |

## Privacy note

The slice reads MediaStore rows only; no doc here carries a real path. See
`docs/README.md`.
