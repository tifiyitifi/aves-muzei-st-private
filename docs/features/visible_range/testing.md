# Visible range — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Host tests | `.flutter/bin/flutter.bat test test/features/visible_range` | do the model, store, gate, lock and page rules hold |
| Rule register | `pwsh -NoProfile -File scripts/check-visible-range-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it hold where the wallpaper and the library meet |

## Fixtures

- The model tests are pure: a range is built from filters and resolved in
  memory, so the two orders are compared against the same expression tree.
- Store and controller tests use an in-memory database injected through
  `VisibleRangeController(injectedDatabase: ...)`.
- The page tests use `testWidgets` and the app's own tiles; they need no device.
- Database tests need a full native sqlite3 on Windows (see `AGENTS.md`).
- `visible_range_presets.json` is parsed from the real asset, so a malformed
  bundle fails the suite rather than only the device.

## Device checklist

1. Enable a range with a base and one restriction. Expect the grid, the album
   count and the cover to agree. (`GAT-3`)
2. Add a supplement. Expect entries outside the base to appear and the counts to
   follow. (`MOD-3`)
3. Switch the order to union-first. Expect the supplement to be narrowed by the
   restriction. (`MOD-4`)
4. Open a wallpaper group from the range page. Expect browsing to join the group
   range; suspend the gallery range, leave the page, and expect the gallery range
   back. (`GAT-5`, `GAT-7`, `GAT-8`)
5. Lock the gallery range with the read-only preset. Expect delete, move and edit
   to be withheld while sharing still works. (`LCK-2`)
6. Delete a built-in rule, then bump `defaultsVersion` and restart. Expect the
   rule back, switched off, with user rules intact. (`CTL-10`, `CTL-13`)
7. Save a base preset that names a standard directory. Expect it to resolve on
   the device rather than show a stand-in path. (`DEF-3`)

## Privacy

Describe photos and albums by kind. Never paste a real preset path or album name
into a test or a note.
