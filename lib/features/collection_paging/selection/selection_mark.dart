import 'dart:async';
import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// A selection declared over a whole collection view.
///
/// "Select all" on a windowed collection cannot enumerate a million rows, so the
/// view is marked as a whole and only the *unmarked* rows are remembered: the
/// files the user tapped off, and the traits (filters) the user excluded. The
/// count and the SQL scope are derived from that pair, so the marker costs
/// nothing to hold and answers a tile's highlight in memory.
///
/// The scope only ever shrinks: narrowing the view (adding a filter) intersects
/// the mark with it, exactly as the legacy selection dropped the entries that
/// left the view.
class CollectionSelectionMark extends ChangeNotifier implements SelectionMark<AvesEntry> {
  late CollectionWindowPredicate _scope;

  /// Rows the user tapped off.
  final Set<int> _unmarkedIds = {};

  /// Traits the user excluded: every row matching any of them is unmarked.
  final Set<CollectionFilter> _unmarkedFilters = {};

  late int _count;

  new({required CollectionWindowPredicate scope, required int count}) {
    _scope = scope;
    _count = count;
  }

  @override
  int get count => _count;

  /// The scope an action resolves, with the unmarked rows excluded.
  CollectionWindowPredicate get predicate => CollectionWindowPredicate(
        conjunction: [
          ..._scope.conjunction,
          if (_unmarkedIds.isNotEmpty)
            (
              sql: 'e.id NOT IN (${List.filled(_unmarkedIds.length, '?').join(', ')})',
              variables: [for (final id in _unmarkedIds) Variable(id)],
              requires: const <WindowTable>{},
            ),
          for (final filter in _unmarkedFilters) ..._filterExclusion(filter),
        ],
        trashedOnly: _scope.trashedOnly,
      );

  @override
  bool isMarked(AvesEntry entry) => !_unmarkedIds.contains(entry.id) && !_unmarkedFilters.any((filter) => filter.test(entry));

  @override
  void mark(Iterable<AvesEntry> entries) {
    var changed = false;
    for (final entry in entries) {
      if (_unmarkedIds.remove(entry.id)) changed = true;
    }
    if (!changed) return;
    unawaited(_recount());
    notifyListeners();
  }

  @override
  void unmark(Iterable<AvesEntry> entries) {
    var changed = false;
    for (final entry in entries) {
      if (_unmarkedIds.add(entry.id)) changed = true;
    }
    if (!changed) return;
    // Show the drop at once, then let the database confirm the exact count.
    _count = max(0, _count - 1);
    unawaited(_recount());
    notifyListeners();
  }

  /// Unmarks every row matching [filters], without enumerating them.
  ///
  /// This is how a whole album (or any other trait) is deselected from a marked
  /// view: the rule is remembered, not the rows it matches.
  void unmarkTraits(Set<CollectionFilter> filters) {
    var changed = false;
    for (final filter in filters) {
      if (_unmarkedFilters.add(filter)) changed = true;
    }
    if (!changed) return;
    unawaited(_recount());
    notifyListeners();
  }

  @override
  void clear() {
    _unmarkedIds.clear();
    _unmarkedFilters.clear();
  }

  /// Intersects the marker with the view's current scope.
  ///
  /// A filter the user adds afterwards removes the rows it excludes from the
  /// selection; it never adds rows back.
  void refresh(CollectionWindowPredicate view) {
    if (view.conjunction.isEmpty && !view.trashedOnly) return;
    _scope = CollectionWindowPredicate(
      conjunction: [..._scope.conjunction, ...view.conjunction],
      trashedOnly: _scope.trashedOnly || view.trashedOnly,
    );
    unawaited(_recount());
  }

  Future<void> _recount() async {
    final count = await localMediaDb.countEntries(predicate);
    if (count == _count) return;
    _count = count;
    notifyListeners();
  }

  /// SQL for one excluded trait: the reversal of the filter's own test.
  ///
  /// `COALESCE(<test>, 0) = 0` rather than `NOT (<test>)`, because Dart's
  /// `!test` keeps a row a NULL comparison makes false: a reversed album filter
  /// must keep an entry that has no directory.
  static List<WindowFragment> _filterExclusion(CollectionFilter filter) {
    final fragment = filterTestFragment(filter);
    if (fragment == null) return const [];
    return [(sql: 'COALESCE(${fragment.sql}, 0) = 0', variables: fragment.variables, requires: fragment.requires)];
  }
}
