# Collection paging — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Feature tests | `.flutter/bin/flutter.bat test test/features/collection_paging` | do the engine, sync, catalogue, selection and view rules hold |
| Full suite | `.flutter/bin/flutter.bat test` | did a shared seam (source, database, settings) change |
| Rule register | `pwsh -NoProfile -File scripts/check-collection-paging-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it hold on a real large library |

## Fixtures

- Engine and predicate tests are pure; routing is driven with a fake database
  probe and the app's filter model.
- Lens, sync, catalogue and summary tests use an in-memory Drift database and
  fake platform services from `test/common.dart`.
- The view tests are `testWidgets` against the app's own tiles and page state.
- `paged_sync_test.dart` is the largest fixture: it drives the discoverer against
  a fake `MediaStoreService` and asserts both the rows and the stored cursor.

## The sqlite requirement is load-bearing

Database tests need a full native sqlite3 on Windows; `test/helpers/sqlite3_loader.dart`
fails loudly instead of skipping. Do **not** point `AVES_SQLITE3_DLL` at the
Microsoft build: its `localtime` modifier does not work, so
`datetime('now','localtime')` returns NULL, every month/day section header query
comes back empty, and the paged lens blocks instead of showing rows. See
`AGENTS.md`.

## Device checklist

1. Open a library of at least the threshold size. Expect the grid to paint
   quickly, scroll without a stall, and the album list to show counts.
   (`ENG-4`, `SUM-5`)
2. Kill the app during the first import, relaunch. Expect the import to resume
   and the view to paint before it finishes. (`IMP-1`, `IMP-6`)
3. Add a photo from another app, then return. Expect one new row, no duplicate,
   and the album count to follow. (`SYN-3`, `SYN-7`)
4. Delete a photo from another app. Expect the row gone after the next sync.
   (`SYN-6`)
5. Unmount the SD card and return. Expect no mass deletion. (`SYN-12`)
6. Open a large album, wait for the catalogue prompt, answer "later", and reopen
   the app. Expect it to ask once per session, not once per page. (`CAT-1`,
   `CAT-2`)
7. Start a slideshow over a paged album. Expect a stable random order and no
   loading stall between photos. (`LEN-25`)
8. Select a section header in a narrow date layout, then open the selection.
   Expect the trait to cover the whole section, not only the visible rows.
   (`SEL-11`, `SEL-12`)

## Privacy

Describe the library by size and kind. Never paste a real album name, path or
photo title into a fixture or this file.
