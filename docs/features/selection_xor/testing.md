# Selection XOR range — testing

## Host coverage

`test/features/selection_xor/selection_xor_test.dart` drives the extension on a
plain `Selection<int>`, with an identity-based `_Item` fixture for the key
comparison and a `_Mark` double for the declared-mark path:

- the interval forward and backward, ranging back, the target becoming the
  anchor;
- the four degradation paths (no anchor, anchor missing, target missing, anchor
  pressed);
- key comparison across fresh instances;
- an unselectable row skipped between the endpoints;
- flipping through a mark without enumerating it, and the mark emptying out of
  selection mode.

The anchor lifecycle is owned by `test/model/selection_test.dart` (group `'range
anchor'`), next to the model that implements it; the register cites those tokens
directly.

## What stays device-level

`GridSelectionGestureDetector` has its own widget test
(`test/widgets/common/grid/selector_test.dart`): the press resolves to the row
under the finger (app bar and pinned header subtracted), a press outside the
selectable list starts nothing, and a press outside the page's selection scope is
ignored after a real range has selected two rows.

The paint drag needs a live scroll and timers; a tap during a fling and the
additive/erase behaviour are device-level. `AGENTS.md` §Selection is the review
checklist for a change to the seam.

## Discipline

- A new multi-select surface adds a `GridSelectionGestureDetector`, not a copy of
  the math; a list page without a grid calls `rangeXorTo(orderedItems, item)`.
- `orderedItems` is the visible, selectable list; never pass the full source.
- A test that asserts the anchor compares by key (`anchor?.id`), not by identity.
- A rule about the gesture belongs here; the paint-drag internals belong to the
  widget's own comments.
