import 'package:aves/model/selection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A selection declared over a scope, without a database behind it.
class _Mark extends ChangeNotifier implements SelectionMark<int> {
  @override
  int count = 3;

  final unmarked = <int>{};

  @override
  bool isMarked(int item) => !unmarked.contains(item);

  @override
  void mark(Iterable<int> items) {
    var changed = false;
    for (final item in items) {
      if (unmarked.remove(item)) changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void unmark(Iterable<int> items) {
    var changed = false;
    for (final item in items) {
      if (unmarked.add(item)) changed = true;
    }
    if (changed) {
      count = count - 1;
      notifyListeners();
    }
  }

  @override
  void clear() => unmarked.clear();
}

/// A selection is either an enumerated set or a declared mark; the mark is what
/// keeps a whole view selectable without holding its rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a declared selection answers from its mark, not from a set', () {
    final selection = Selection<int>(toSelectableItems: null);
    selection.markAll(_Mark());

    expect(selection.isSelecting, isTrue);
    expect(selection.allMarked, isTrue);
    expect(selection.selectedItemCount, 3);
    // Nothing is enumerated: the marked rows are declared.
    expect(selection.selectedItems, isEmpty);
    expect(selection.isSelected({1}), isTrue);

    // Unmarking one row is the only state the selection holds.
    selection.removeFromSelection({1});
    expect(selection.isSelected({1}), isFalse);
    expect(selection.isSelected({2}), isTrue);
    expect(selection.selectedItemCount, 2);
  });

  test('a declared selection leaves selection mode once its scope empties', () {
    final selection = Selection<int>(toSelectableItems: null);
    final mark = _Mark()..count = 1;
    selection.markAll(mark);

    selection.removeFromSelection({1});

    expect(selection.isSelecting, isFalse);
    expect(selection.allMarked, isFalse);
    expect(selection.selectedItemCount, 0);
  });

  test('clearing a declared selection drops the mark', () {
    final selection = Selection<int>(toSelectableItems: null);
    selection.markAll(_Mark());

    selection.clearSelection();

    expect(selection.allMarked, isFalse);
    expect(selection.selectedItemCount, 0);
  });

  test('an enumerated selection is untouched by the mark support', () {
    final selection = Selection<int>(toSelectableItems: null);
    selection.addToSelection({1, 2});

    expect(selection.allMarked, isFalse);
    expect(selection.selectedItemCount, 2);
    expect(selection.isSelected({1, 2}), isTrue);
    expect(selection.isSelected({1, 3}), isFalse);
  });

  // The anchor is the fixed end of a range gesture: a tap moves it, a range or a
  // section-wide pick must not, and anything that drops the selection drops it.
  group('range anchor', () {
    test('the last single toggle becomes the anchor', () {
      final selection = Selection<int>(toSelectableItems: null);

      selection.toggleSelection(2);
      expect(selection.anchor, 2);

      selection.toggleSelection(5);
      expect(selection.anchor, 5);
    });

    test('an added range does not move the anchor', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(2);

      selection.addToSelection({7, 8});

      expect(selection.anchor, 2);
    });

    test('leaving selection mode clears the anchor', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(2);

      selection.browse();

      expect(selection.anchor, isNull);
    });

    test('clearing the selection clears the anchor', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(2);

      selection.clearSelection();

      expect(selection.anchor, isNull);
    });

    test('a whole-scope mark has no anchor to range from', () {
      final selection = Selection<int>(toSelectableItems: null);
      selection.toggleSelection(2);

      selection.markAll(_Mark());

      expect(selection.anchor, isNull);
    });
  });
}
