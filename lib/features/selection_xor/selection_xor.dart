import 'package:aves/model/selection.dart';

/// Range selection from the last toggled item.
///
/// A tap toggles one item and moves the anchor. A long press while already
/// selecting flips every item between that anchor and the pressed item instead,
/// so a long list can be adjusted in one gesture without losing the items
/// picked before it. The flip excludes the anchor and includes the target:
/// ranging back undoes exactly what ranging forward added, except for the two
/// endpoints, which is what makes repeated ranges composable.
extension SelectionXor<T> on Selection<T> {
  /// Flips the items of [orderedItems] between the anchor and [target].
  ///
  /// [orderedItems] must hold the selectable items in display order, which is
  /// what the grid already passes to its gesture layer: unselectable rows are
  /// not part of that list, so an interval is taken across them rather than
  /// stopping at them.
  ///
  /// Degrades to a single toggle when no interval can be determined: no anchor
  /// (a selection started by a whole-scope mark or a section-level action), or
  /// either end missing from [orderedItems] because the row was filtered out or
  /// scrolled out of the list the gesture computed against. Pressing the anchor
  /// itself toggles it as well, because an empty interval would make the gesture
  /// look unresponsive.
  void rangeXorTo(List<T> orderedItems, T target) {
    final anchorItem = anchor;
    if (anchorItem == null) {
      toggleSelection(target);
      return;
    }

    final anchorIndex = orderedItems.indexWhere((item) => isSameItem(item, anchorItem));
    final targetIndex = orderedItems.indexWhere((item) => isSameItem(item, target));
    if (anchorIndex == -1 || targetIndex == -1 || anchorIndex == targetIndex) {
      toggleSelection(target);
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex + 1 : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex - 1;

    // Partition first so the whole interval lands in one mark/unmark pass: the
    // two sets are disjoint by construction, so the mark path cannot interleave
    // a mark with an unmark of the same item.
    final toUnselect = <T>[];
    final toSelect = <T>[];
    for (var i = start; i <= end; i++) {
      final item = orderedItems[i];
      (isSelected([item]) ? toUnselect : toSelect).add(item);
    }
    removeFromSelection(toUnselect);
    addToSelection(toSelect);

    // The range continues from its target, so a following range or a drag that
    // starts here keeps working from what the user last touched.
    moveAnchorTo(target);
  }
}
