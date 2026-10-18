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
}
