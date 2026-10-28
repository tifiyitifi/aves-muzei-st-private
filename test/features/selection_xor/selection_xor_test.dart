import 'package:aves/features/selection_xor/selection_xor.dart';
import 'package:aves/model/selection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A declared scope whose marked rows are never enumerated.
class _Mark extends ChangeNotifier implements SelectionMark<int> {
  new(this.count);

  @override
  int count;

  final unmarked = <int>{};

  @override
  bool isMarked(int item) => !unmarked.contains(item);

  @override
  void mark(Iterable<int> items) {
    for (final item in items) {
      if (unmarked.remove(item)) count++;
    }
    notifyListeners();
  }

  @override
  void unmark(Iterable<int> items) {
    for (final item in items) {
      if (unmarked.add(item)) count--;
    }
    notifyListeners();
  }

  @override
  void clear() => unmarked.clear();
}

/// An identity-based item, like an entry read from the database: the list a
/// gesture reads holds fresh instances of the same rows.
class _Item {
  final int id;

  const new(this.id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interval', () {
    test('flips every item after the anchor up to the target', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(0);

      selection.rangeXorTo([0, 1, 2, 3], 3);

      // The anchor itself is not flipped; the target is.
      expect(selection.selectedItems, {0, 1, 2, 3});
      expect(selection.anchor, 3);
    });

    test('ranging back undoes the interval it crossed before', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(0);
      selection.rangeXorTo([0, 1, 2, 3], 3);

      selection.rangeXorTo([0, 1, 2, 3], 1);

      // Both endpoints survive, only what the ranges crossed is flipped back.
      expect(selection.selectedItems, {0, 3});
      expect(selection.anchor, 1);
    });

    test('flips backwards as well as forwards', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(3);

      selection.rangeXorTo([0, 1, 2, 3], 0);

      expect(selection.selectedItems, {0, 1, 2, 3});
      expect(selection.anchor, 0);
    });

    test('resolves the anchor and the target by key, not by instance', () {
      final selection = Selection<_Item>(toSelectableItems: null, keyOf: (item) => item.id);
      selection.toggleSelection(const _Item(1));
      final listed = [const _Item(1), const _Item(2), const _Item(3)];

      selection.rangeXorTo(listed, listed[2]);

      expect(selection.selectedItems.map((v) => v.id).toSet(), {1, 2, 3});
      expect(selection.anchor?.id, 3);
    });
  });

  group('degradation', () {
    test('a selection with no anchor toggles the target alone', () {
      final selection = Selection<int>(toSelectableItems: null)..select();

      selection.rangeXorTo([0, 1, 2], 2);

      expect(selection.selectedItems, {2});
    });

    test('an anchor outside the ordered list toggles the target alone', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(9);

      selection.rangeXorTo([0, 1, 2], 2);

      expect(selection.selectedItems, {9, 2});
    });

    test('a target outside the ordered list toggles it alone', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(0);

      selection.rangeXorTo([0, 1, 2], 9);

      expect(selection.selectedItems, {0, 9});
    });

    test('pressing the anchor again toggles it instead of doing nothing', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(0);

      selection.rangeXorTo([0, 1, 2], 0);

      expect(selection.selectedItems, isEmpty);
      expect(selection.anchor, 0);
    });
  });

  group('declared mark', () {
    test('an interval flips through the mark without enumerating it', () {
      final selection = Selection<int>(toSelectableItems: null);
      final mark = _Mark(5);
      selection.markAll(mark);
      // A whole-scope mark has no order, so it clears the anchor.
      expect(selection.anchor, isNull);

      selection.toggleSelection(1);
      selection.rangeXorTo([0, 1, 2, 3, 4], 3);

      expect(mark.unmarked, {1, 2, 3});
      expect(selection.selectedItemCount, 2);
      expect(selection.allMarked, isTrue);
    });
  });
}
