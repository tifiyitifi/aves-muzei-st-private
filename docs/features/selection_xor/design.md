# Selection XOR range — design

## The interval

```text
anchorIndex = list.indexWhere(isSameItem(anchor))
targetIndex = list.indexWhere(isSameItem(target))

absent anchor, absent target, or the same index -> toggle(target)
forward:  flip list[anchorIndex + 1 .. targetIndex]
backward: flip list[targetIndex .. anchorIndex - 1]
```

Exclude the anchor, include the target. That is the only interval shape that is
self-inverse on its interior: `A -> B` flips the rows strictly between them plus
B, and `B -> A` flips the same interior plus A's neighbour set, restoring every
interior row while both endpoints keep their state. Asking for a range twice
therefore returns to the same selection, and two consecutive ranges compose
instead of replacing.

The same-index case is folded into the degradation branch: flipping an empty
interval would make the gesture look unresponsive, so pressing the anchor toggles
it. `-1` on either end is the "row filtered out or no longer in the list" case; an
index-based flip would silently land on a neighbour.

## One pass, two disjoint sets

The loop partitions the interval into `toUnselect` (currently selected) and
`toSelect` (currently unselected), then calls `removeFromSelection` followed by
`addToSelection`. The sets are disjoint by construction, so a declared mark
cannot see a `mark` and an `unmark` of the same item interleaved within one
gesture, which matters when membership depends on the last operation.

After the flip, the anchor moves to the target **only while the selection is
still active**. If the flip emptied a declared mark, `Selection` has already left
selection mode and dropped its anchor; moving it back would leave a range origin
with no selection behind it, and the next long press on a list page (which calls
`rangeXorTo` unconditionally) would flip from a phantom anchor.

## The anchor

`Selection` owns a `T? _anchor` — the item, not an index. Grids rebuild their
lists from fresh instances (a database read returns new `AvesEntry`s), so an
index would point at a neighbour after a refresh. Comparison is always through
`isSameItem`/`keyOf`.

`toggleSelection` sets the anchor on every toggle, including a deselecting tap;
`moveAnchorTo` sets it without toggling. `browse`, `clearSelection` and `markAll`
drop it; `addToSelection`/`removeFromSelection` leave it alone. No page keeps an
anchor of its own: call sites pass only the visible ordered items.

## The ordered list contract

`orderedItems` must hold the selectable rows in display order. A filter grid
passes its visible, applicable rows, so unselectable rows never enter the
interval; the interval is taken across the gap rather than stopping at it.
`AGENTS.md` states the consequence: unselectable rows are skipped, never flipped
through.

## The gesture seam

`GridSelectionGestureDetector` is the single seam:

- long press while selecting -> `rangeXorTo(scopedItems, pressedItem)`;
- long press while not selecting -> `toggleSelection(pressedItem)`;
- after the flip it records the pressed row as the start of the *paint* drag,
  which is a separate contribution: the flip settles what the gesture crossed,
  the drag owns what it paints afterwards. The first painted step therefore does
  not double-flip the pressed row.

A press outside the page's selection scope returns before any mutation, so a
press in another grid does nothing.

## Anti-patterns

- Keeping the anchor in a page: every page would have its own stale origin.
- Using an index as the anchor: a list rebuild moves it.
- Treating the interval as "select from A to B" instead of a flip: ranging back
  would have to unselect everything, losing rows picked before the range.
- Unifying the flip and the paint drag: the first paint step would flip the
  pressed row twice.
