# Visible range — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Host tests | `.flutter/bin/flutter.bat test test/features/visible_range` | do the model, store, gate, lock, page and editor rules hold |
| Rule register | `pwsh -NoProfile -File scripts/check-visible-range-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it hold where the wallpaper and the library meet |

## Fixtures

- The model tests are pure: a range is built from filters and resolved in
  memory, so the two orders are compared against the same expression tree.
- The page-layout tests build `buildVisibleRangePageSections` directly: section
  order, the sentinel tile and the group's joined filter need no widget tree.
- Store and controller tests use an in-memory database injected through
  `VisibleRangeController(injectedDatabase: ...)`. A data group is created when a
  test needs a writable container; group 0 is the 「Unrestricted」 sentinel.
- The tile and section-header tests use `testWidgets` and the app's own widgets;
  they need no device.
- Database tests need a full native sqlite3 on Windows (see `AGENTS.md`).
- `visible_range_presets.json` is parsed from the real asset, so a malformed
  bundle fails the suite rather than only the device.

## Device checklist

1. Open the range page. Expect four sections in this order: groups, outside
   restrictions, outside supplements, currently visible. Group 0 reads
   「Unrestricted」, is first and has no conditions. (`PAGE-1`, `GRP-1`)
2. Long-press a data group. Expect the overflow to offer edit / rename / move /
   delete, and no editor on group 0. (`GRP-2`, `GRP-3`)
3. Edit a group, switch one condition off, close and discard. Expect the grid
   unchanged. Repeat and save; expect browsing, the tile count and the result to
   follow. (`GRP-6`)
4. Toggle an outside restriction. Expect every group to be narrowed and the
   outside header count to follow. (`PAGE-3`, `MOD-11`)
5. Save the current media set with 「save to visible range」. Expect the two
   outside targets to show `AND` / `OR` instead of the same `0`, and group 0 to
   be absent. (`SAVE-1`, `GRP-2`)
6. Open the wallpaper page and then the group editor. Expect both bar entries on
   the configured side, the first opened adjacent to the range entry; close the
   editor and expect the range page. (`NAV-6`, `NAV-7`)
7. Open a wallpaper group from the range page. Expect browsing to join the group
   range; suspend the gallery range, leave the page, and expect the gallery range
   back. (`GAT-5`, `GAT-7`, `GAT-8`)
8. Lock the gallery range with the read-only preset. Expect delete, move and edit
   to be withheld while sharing still works; the editor refuses to open.
   (`LCK-2`, `GRP-1`)
9. Delete a built-in rule, then bump `defaultsVersion` and restart. Expect the
   rule back, switched off, with user rules intact. (`CTL-14`, `CTL-17`)
10. Save a preset that names a standard directory. Expect it to resolve on the
    device rather than show a stand-in path. (`DEF-3`)

## Privacy

Describe photos and albums by kind. Never paste a real preset path or album name
into a test or a note.
