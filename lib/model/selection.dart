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

class Selection<T> extends ChangeNotifier {
  final SelectionKeyOf<T> _keyOf;

  late final Iterable<T> Function(Iterable<T> items) _expandToSelectableItems;

  bool _isSelecting = false;

  bool get isSelecting => _isSelecting;

  /// Selected items by key, so the instance that was added first wins and the
  /// count never doubles for one underlying item.
  final Map<Object?, T> _selectedItems = {};

  int get selectedItemCount => _selectedItems.length;

  Set<T> get selectedItems => Set.unmodifiable(_selectedItems.values);

  new({required ToSelectableItems<T>? toSelectableItems, SelectionKeyOf<T>? keyOf}) : _keyOf = keyOf ?? ((item) => item) {
    if (kFlutterMemoryAllocationsEnabled) ChangeNotifier.maybeDispatchObjectCreation(this);

    if (toSelectableItems != null) {
      _expandToSelectableItems = (items) => _loadedItems(items).expand(toSelectableItems);
    } else {
      _expandToSelectableItems = _loadedItems;
    }
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

  bool isSelected(Iterable<T> items) => _expandToSelectableItems(items).every((item) => _selectedItems.containsKey(_keyOf(item)));

  int countSelectable(Iterable<T> items) => _expandToSelectableItems(items).map(_keyOf).toSet().length;

  int countSelected(Iterable<T> items) => _expandToSelectableItems(items).map(_keyOf).where(_selectedItems.containsKey).length;

  void addToSelection(Iterable<T> items) {
    if (items.isEmpty) return;

    select();
    for (final item in _expandToSelectableItems(items)) {
      _selectedItems[_keyOf(item)] = item;
    }
    notifyListeners();
  }

  void removeFromSelection(Iterable<T> items) {
    if (items.isEmpty) return;

    for (final item in _expandToSelectableItems(items)) {
      _selectedItems.remove(_keyOf(item));
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedItems.clear();
    notifyListeners();
  }

  void toggleSelection(T item) {
    if (!_isSelecting) select();

    final selectableItems = _expandToSelectableItems({item});
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
}
