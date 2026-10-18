import 'dart:async';
import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// What a whole-view selection covers on a windowed view.
///
/// Two scopes, because a view and a selection count different rows when stacks
/// are collapsed: the view shows a tile, the selection expands it to every member
/// it hides. An action walks [tiles]; the count and the confirmation dialogs
/// report [entries], exactly like the legacy selection did.
class SelectionScope {
  /// Rows the view shows: stacks collapsed to their tile.
  final CollectionWindowPredicate tiles;

  /// Rows the selection expands to: the tiles plus the members they hide.
  final CollectionWindowPredicate entries;

  /// True when the view projects one row per day (the calendar layout).
  ///
  /// The view then counts days while a selection still covers their entries, so
  /// a walk yields entries where the tiles are days.
  final bool dayRows;

  const new({required this.tiles, required this.entries, this.dayRows = false});
}

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
  /// The view's scopes, intersected with every later view.
  late CollectionWindowPredicate _tiles;
  late CollectionWindowPredicate _entries;

  /// The last view seen, so a repeated collection change does not intersect the
  /// same scope over and over.
  CollectionWindowPredicate? _lastView;

  late bool _dayRows;

  /// Rows the user tapped off.
  final Set<int> _unmarkedIds = {};

  /// Traits the user excluded: every row matching any of them is unmarked.
  final Set<CollectionFilter> _unmarkedFilters = {};

  late int _count;
  late int _expandedCount;

  new({required SelectionScope scope, required int count, int? expandedCount}) {
    _tiles = scope.tiles;
    _entries = scope.entries;
    _lastView = scope.tiles;
    _dayRows = scope.dayRows;
    _count = count;
    _expandedCount = expandedCount ?? count;
  }

  /// Rows the view shows as items.
  ///
  /// This is the count the app bar compares with the view's own total, so the
  /// two always agree and "select none" stays reachable. Under the calendar
  /// projection it counts days.
  @override
  int get count => _count;

  /// Rows the selection expands to, stack members included: what an action
  /// actually touches, and what its dialogs must report.
  int get expandedCount => _expandedCount;

  /// Rows a walk yields: the view's tiles, or the entries themselves under the
  /// calendar projection, whose tiles are days.
  int get walkCount => _dayRows ? _expandedCount : _count;

  /// The scope an action walks, with the unmarked rows excluded.
  CollectionWindowPredicate get tilePredicate => _exclude(_tiles);

  /// The scope a count reports, with the unmarked rows excluded.
  CollectionWindowPredicate get entryPredicate => _exclude(_entries);

  CollectionWindowPredicate _exclude(CollectionWindowPredicate scope) => CollectionWindowPredicate(
        conjunction: [
          ...scope.conjunction,
          if (_unmarkedIds.isNotEmpty)
            (
              sql: 'e.id NOT IN (${List.filled(_unmarkedIds.length, '?').join(', ')})',
              variables: [for (final id in _unmarkedIds) Variable(id)],
              requires: const <WindowTable>{},
            ),
          for (final filter in _unmarkedFilters) ..._filterExclusion(filter),
        ],
        trashedOnly: scope.trashedOnly,
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
    _expandedCount = max(0, _expandedCount - 1);
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

  /// Intersects the marker with the view's current scopes.
  ///
  /// A filter the user adds afterwards removes the rows it excludes from the
  /// selection; it never adds rows back.
  void refresh(SelectionScope view) {
    if (_sameScope(_lastView, view.tiles)) return;
    _lastView = view.tiles;
    _dayRows = view.dayRows;
    _tiles = _intersect(_tiles, view.tiles);
    _entries = _intersect(_entries, view.entries);
    unawaited(_recount());
  }

  /// Re-reads both counts from the database.
  ///
  /// An action that removed rows leaves the seeded counts stale; the view's
  /// scope itself did not change, so nothing else would refresh them.
  Future<void> recount() => _recount();

  Future<void> _recount() async {
    final walk = await localMediaDb.countEntries(tilePredicate);
    final count = _dayRows ? await localMediaDb.countDays(predicate: tilePredicate) : walk;
    final expanded = _dayRows || _sameScope(_tiles, _entries) ? walk : await localMediaDb.countEntries(entryPredicate);
    if (count == _count && expanded == _expandedCount) return;
    _count = count;
    _expandedCount = expanded;
    notifyListeners();
  }

  /// Whether two scopes compile to the same SQL.
  ///
  /// The lens re-resolves its predicate on every refresh (a media store event, a
  /// settings change), so identity would treat an unchanged view as a narrowing
  /// one and stack the same fragments over and over.
  static bool _sameScope(CollectionWindowPredicate? a, CollectionWindowPredicate b) {
    if (a == null || a.trashedOnly != b.trashedOnly || a.conjunction.length != b.conjunction.length) return false;
    for (var i = 0; i < a.conjunction.length; i++) {
      if (a.conjunction[i].sql != b.conjunction[i].sql) return false;
    }
    return true;
  }

  static CollectionWindowPredicate _intersect(CollectionWindowPredicate a, CollectionWindowPredicate b) => CollectionWindowPredicate(
        conjunction: [...a.conjunction, ...b.conjunction],
        trashedOnly: a.trashedOnly || b.trashedOnly,
      );

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
