import 'package:flutter/foundation.dart';

typedef ToSelectableItems<T> = Set<T> Function(T item);

/// Identity of a selectable item.
///
/// Two instances of the same underlying item must count as one selection entry:
/// an entry can be served by several database reads, and the tile the grid shows
/// is not necessarily the instance an action collected. Defaults to the item
/// itself, which is what a value-typed item wants.
typedef SelectionKeyOf<T> = Object? Function(T item);

/// An [Iterable] whose positions may be placeholders until their rows load.
///
/// A windowed collection serves its whole list and each section as a
/// fixed-length lazy list: reading a position can kick work and hand back a
/// placeholder. A selection never wants those placeholders and must not walk the
/// list to find out, so it reads [loadedItems] instead of iterating.
abstract interface class SelectionLazySource<T> {
  /// The real, loaded items of this source, in index order.
  Iterable<T> get loadedItems;
}

/// A selection declared over a whole scope instead of enumerated.
///
/// A windowed collection can mark a million rows without holding them, so the
/// mark answers membership and count itself and remembers only the rows the user
/// unmarked. [Selection] forwards every mutation to it while [Selection.allMarked],
/// and keeps its enumerated set for the legacy path.
abstract interface class SelectionMark<T> {
  /// Number of marked items. Declared; the mark never enumerates them.
  int get count;

  /// Whether [item] is marked.
  bool isMarked(T item);

  /// Marks [items] again, undoing an earlier unmark.
  void mark(Iterable<T> items);

  /// Unmarks [items]: the user tapped them off.
  void unmark(Iterable<T> items);

  /// Drops the mark's own state.
  void clear();
}

class Selection<T> extends ChangeNotifier {
  final SelectionKeyOf<T> _keyOf;

  late final Iterable<T> Function(Iterable<T> items) _expandToSelectableItems;

  bool _isSelecting = false;

  bool get isSelecting => _isSelecting;

  /// The mark this selection is declared over, when it is not an enumerated set.
  SelectionMark<T>? _mark;

  SelectionMark<T>? get mark => _mark;

  /// Whether the selection is a whole-scope mark rather than a set of items.
  bool get allMarked => _mark != null;

  /// Selected items by key, so the instance that was added first wins and the
  /// count never doubles for one underlying item. Empty under a mark: the marked
  /// items are declared, not held.
  final Map<Object?, T> _selectedItems = {};

  int get selectedItemCount => _mark?.count ?? _selectedItems.length;

  Set<T> get selectedItems => _mark != null ? const {} : Set.unmodifiable(_selectedItems.values);

  new({required ToSelectableItems<T>? toSelectableItems, SelectionKeyOf<T>? keyOf}) : _keyOf = keyOf ?? ((item) => item) {
    if (kFlutterMemoryAllocationsEnabled) ChangeNotifier.maybeDispatchObjectCreation(this);

    if (toSelectableItems != null) {
      _expandToSelectableItems = (items) => _loadedItems(items).expand(toSelectableItems);
    } else {
      _expandToSelectableItems = _loadedItems;
    }
  }

  @override
  void dispose() {
    _detachMark();
    super.dispose();
  }

  /// The items a selection query can look at: everything, unless the source is a
  /// lazy one, in which case only its loaded rows.
  Iterable<T> _loadedItems(Iterable<T> items) {
    final Object source = items;
    return source is SelectionLazySource<T> ? source.loadedItems : items;
  }

  void browse() {
    if (!_isSelecting) return;
    _isSelecting = false;
    _mark?.clear();
    _detachMark();
    _selectedItems.clear();
    notifyListeners();
  }

  void select() {
    if (_isSelecting) return;
    // clear selection on `select`, not on `browse`, so that
    // the selection count is stable when transitioning to browse
    clearSelection();
    _isSelecting = true;
    notifyListeners();
  }

  /// Declares the whole scope marked, instead of enumerating it.
  void markAll(SelectionMark<T> mark) {
    _detachMark();
    _selectedItems.clear();
    _mark = mark;
    if (mark is Listenable) (mark as Listenable).addListener(notifyListeners);
    _isSelecting = true;
    notifyListeners();
  }

  bool isSelected(Iterable<T> items) {
    final mark = _mark;
    final expanded = _expandToSelectableItems(items);
    if (mark != null) return expanded.every(mark.isMarked);
    return expanded.every((item) => _selectedItems.containsKey(_keyOf(item)));
  }

  int countSelectable(Iterable<T> items) {
    final mark = _mark;
    final expanded = _expandToSelectableItems(items);
    if (mark != null) return expanded.where(mark.isMarked).length;
    return expanded.map(_keyOf).toSet().length;
  }

  int countSelected(Iterable<T> items) {
    final mark = _mark;
    final expanded = _expandToSelectableItems(items);
    if (mark != null) return expanded.where(mark.isMarked).length;
    return expanded.map(_keyOf).where(_selectedItems.containsKey).length;
  }

  void addToSelection(Iterable<T> items) {
    if (items.isEmpty) return;

    final mark = _mark;
    if (mark != null) {
      final expanded = _expandToSelectableItems(items);
      if (expanded.isEmpty) return;
      mark.mark(expanded);
      notifyListeners();
      return;
    }

    select();
    for (final item in _expandToSelectableItems(items)) {
      _selectedItems[_keyOf(item)] = item;
    }
    notifyListeners();
  }

  void removeFromSelection(Iterable<T> items) {
    if (items.isEmpty) return;

    final mark = _mark;
    if (mark != null) {
      final expanded = _expandToSelectableItems(items);
      if (expanded.isEmpty) return;
      mark.unmark(expanded);
      notifyListeners();
      return;
    }

    for (final item in _expandToSelectableItems(items)) {
      _selectedItems.remove(_keyOf(item));
    }
    notifyListeners();
  }

  void clearSelection() {
    _mark?.clear();
    _detachMark();
    _selectedItems.clear();
    notifyListeners();
  }

  void toggleSelection(T item) {
    if (!_isSelecting) select();

    final mark = _mark;
    final selectableItems = _expandToSelectableItems({item});
    if (mark != null) {
      if (isSelected(selectableItems)) {
        mark.unmark(selectableItems);
      } else {
        mark.mark(selectableItems);
      }
      notifyListeners();
      return;
    }

    if (isSelected(selectableItems)) {
      for (final selectableItem in selectableItems) {
        _selectedItems.remove(_keyOf(selectableItem));
      }
    } else {
      for (final selectableItem in selectableItems) {
        _selectedItems[_keyOf(selectableItem)] = selectableItem;
      }
    }
    notifyListeners();
  }

  void _detachMark() {
    final mark = _mark;
    if (mark is Listenable) (mark as Listenable).removeListener(notifyListeners);
    _mark = null;
  }
}
