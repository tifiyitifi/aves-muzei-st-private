# Selection XOR range

Picking a long run of rows is one gesture, not N taps: a tap moves the anchor, a
long press flips everything between the anchor and the pressed row. The same
extension serves the collection grid, every filter grid and the three list pages
that own their ordered rows.

Status: **in progress**. The extension, the anchor in `Selection` and the grid
seam are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- the interval math: exclude the anchor, include the target, flip each row;
- degradation to a single toggle when no interval can be determined;
- anchor ownership in `Selection` (an item compared by key, not an index);
- the declared-mark path, which flips without enumerating the scope;
- the shared gesture seam (`GridSelectionGestureDetector`).

Out of scope:

- paint-drag: the long press starts a separate additive/erase contribution;
- single-item pick pages and the viewer's one-entry toggle;
- section-wide picks, which stay all-or-nothing;
- TV focus and desktop `Shift+click` ranges.

## Version facts

| Fact | Value |
| --- | --- |
| Extension | `Selection.rangeXorTo(List<T>, T)` |
| Anchor owner | `Selection` (`lib/model/selection.dart`) |
| Anchor comparison | `Selection.isSameItem` / `keyOf` |
| Gesture seam | `lib/widgets/common/grid/selector.dart` |
| Direct call sites | grouped wallpaper page, effects sync page, batch results, refra records |
| Rule check | `scripts/check-selection-xor-rules.ps1` |

## Reading order

1. `spec.md` — the gesture as behaviour.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the interval math, the anchor and the mark path.
4. `decisions/` — why XOR, why the anchor lives in `Selection`, why drag is
   separate.
5. `testing.md` — the fixtures and what stays device-level.

## Code map

| Layer | Path |
| --- | --- |
| Interval | `lib/features/selection_xor/selection_xor.dart` |
| Anchor and mark | `lib/model/selection.dart` |
| Gesture seam | `lib/widgets/common/grid/selector.dart` |
| Collection grid | `lib/widgets/collection/collection_grid.dart` |
| Filter grids | `lib/widgets/filter_grids/common/filter_grid_page.dart` |
| Tests | `test/features/selection_xor/`, `test/model/selection_test.dart` |

`AGENTS.md` §Selection (XOR-range) is the normative summary this directory
expands; a change to the gesture updates both.

## Privacy note

Test fixtures use numbered rows, never a real path or title. See
`docs/README.md`.
