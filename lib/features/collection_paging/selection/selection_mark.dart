import 'dart:async';
import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/selection/selection_trait.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// A SQL fragment carrying its own variables, so parts can be concatenated in
/// the exact order their placeholders appear.
typedef _Sql = ({String sql, List<Variable> variables});

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
/// view is marked as a whole and only what leaves the mark is remembered, in
/// three layers of decreasing priority:
///
///  * a manual tap on a tile, which always wins and is not ordered;
///  * a trait history: "select/deselect every row of this album, month, rating,
///    tag, location", appended by a section header or the trait sheet, where for
///    a row several traits cover the *last* op covering it decides;
///  * the view's own scope, which marks everything no trait op covers.
///
/// The count, the walk and a tile's highlight are all derived from that, so the
/// marker costs nothing to hold — it never enumerates the rows it covers.
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

  /// Trait operations, oldest first. Append-only: the last op covering a row
  /// decides, and undoing one appends its opposite.
  final List<SelectionTraitOp> _ops = [];

  /// Rows the user tapped on, above every trait.
  final Set<int> _manualSelected = {};

  /// Rows the user tapped off, above every trait. Disjoint from
  /// [_manualSelected]: the later tap of the two wins.
  final Set<int> _manualUnselected = {};

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

  /// The trait history, oldest first, for the sheet that lets the user undo one.
  List<SelectionTraitOp> get ops => List.unmodifiable(_ops);

  /// The scope an action walks, with the unmarked rows excluded.
  CollectionWindowPredicate get tilePredicate => _compose(_tiles);

  /// The scope a count reports, with the unmarked rows excluded.
  CollectionWindowPredicate get entryPredicate => _compose(_entries);

  CollectionWindowPredicate _compose(CollectionWindowPredicate scope) {
    final mark = _markWhere();
    if (mark == null) return scope;
    return CollectionWindowPredicate(
      conjunction: [
        ...scope.conjunction,
        (
          sql: mark.sql,
          variables: mark.variables,
          // The traits read the tables their own fragments declare, so a count
          // and a walk join exactly what they touch.
          requires: {for (final op in _ops) ...op.trait.fragment.requires},
        ),
      ],
      trashedOnly: scope.trashedOnly,
    );
  }

  @override
  bool isMarked(AvesEntry entry) {
    final id = entry.id;
    if (_manualSelected.contains(id)) return true;
    if (_manualUnselected.contains(id)) return false;
    // The last op covering the row decides; a row no op covers keeps the view's
    // own default, marked.
    for (var i = _ops.length - 1; i >= 0; i--) {
      final op = _ops[i];
      if (op.trait.test(entry)) return op.select;
    }
    return true;
  }

  @override
  void mark(Iterable<AvesEntry> entries) {
    var gained = 0;
    for (final entry in entries) {
      // Already marked by the view or a trait: a tap adds nothing, and must not
      // claim a row the count already holds.
      if (isMarked(entry)) continue;
      final id = entry.id;
      _manualUnselected.remove(id);
      if (_manualSelected.add(id)) gained++;
    }
    if (gained == 0) return;
    // Show the rise at once, then let the database confirm the exact count.
    _count += gained;
    _expandedCount += gained;
    unawaited(_recount());
    notifyListeners();
  }

  @override
  void unmark(Iterable<AvesEntry> entries) {
    var lost = 0;
    for (final entry in entries) {
      if (!isMarked(entry)) continue;
      final id = entry.id;
      _manualSelected.remove(id);
      if (_manualUnselected.add(id)) lost++;
    }
    if (lost == 0) return;
    // Show the drop at once, then let the database confirm the exact count.
    _count = max(0, _count - lost);
    _expandedCount = max(0, _expandedCount - lost);
    unawaited(_recount());
    notifyListeners();
  }

  /// Appends a trait operation selecting every row of [trait].
  ///
  /// This is how a section the user had deselected is taken back, and how a
  /// trait is selected without enumerating its rows.
  void selectTrait(SelectionTrait trait, {required String label}) => _appendTrait(trait, select: true, label: label);

  /// Appends a trait operation deselecting every row of [trait].
  ///
  /// This is how a whole album (or any other trait) is deselected from a marked
  /// view: the rule is remembered, not the rows it matches.
  void deselectTrait(SelectionTrait trait, {required String label}) => _appendTrait(trait, select: false, label: label);

  /// A trait op never touches the manual layers: a row the user tapped stays
  /// exactly as tapped, whatever traits are added around it.
  void _appendTrait(SelectionTrait trait, {required bool select, required String label}) {
    _ops.add(SelectionTraitOp(trait: trait, select: select, label: label));
    unawaited(_recount());
    notifyListeners();
  }

  @override
  void clear() {
    _ops.clear();
    _manualSelected.clear();
    _manualUnselected.clear();
  }

  /// Intersects the marker with the view's current scopes.
  ///
  /// A filter the user adds afterwards removes the rows it excludes from the
  /// selection; it never adds rows back. The trait history needs no adjustment:
  /// the whole mark is already intersected with the new scope.
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

  /// SQL of the mark's own layers, or null when the mark covers the whole scope.
  ///
  /// The trait history expands to "the last op covering a row decides": the
  /// region no op covers, plus, for every selecting op, the region where it is
  /// the last op that covers a row. A manual tap then pierces every trait — the
  /// manually marked rows are unioned in, and the manually unmarked ones removed
  /// last — so a tap stays above the whole history whatever its order.
  _Sql? _markWhere() {
    final manualSelected = _manualSelected;
    final manualUnselected = _manualUnselected;
    if (_ops.isEmpty && manualSelected.isEmpty && manualUnselected.isEmpty) return null;

    final parts = <_Sql>[];
    if (manualSelected.isNotEmpty) parts.add(_idIn(manualSelected, negated: false));

    final traits = _traitWhere(_ops);
    if (traits != null) {
      parts.add(manualUnselected.isEmpty ? traits : _and([traits, _idIn(manualUnselected, negated: true)]));
    } else {
      // Only manual drops: every other row keeps the view's own default, marked.
      parts.add(_idIn(manualUnselected, negated: true));
    }
    return _or(parts);
  }

  /// The trait history as one predicate, or null when no op was recorded.
  static _Sql? _traitWhere(List<SelectionTraitOp> ops) {
    if (ops.isEmpty) return null;
    final regions = <_Sql>[
      // Rows no op covers keep the view's own default, marked.
      _and([for (final op in ops) _traitTest(op.trait, negated: true)]),
    ];
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (!op.select) continue;
      // Only the ops added later can shadow this one.
      regions.add(_and([
        _traitTest(op.trait, negated: false),
        for (var j = i + 1; j < ops.length; j++) _traitTest(ops[j].trait, negated: true),
      ]));
    }
    return _or(regions);
  }

  /// Two-valued SQL of a trait's test, or of its complement.
  ///
  /// `COALESCE(<test>, 0) = 0` rather than `NOT (<test>)`, because Dart's
  /// `!test` keeps a row a NULL comparison makes false: a reversed album filter
  /// must keep an entry that has no directory. The complement is spelled out
  /// here too, so an `OR` around it cannot be swallowed by an unknown.
  static _Sql _traitTest(SelectionTrait trait, {required bool negated}) => (
        sql: 'COALESCE((${trait.fragment.sql}), 0) = ${negated ? 0 : 1}',
        variables: trait.fragment.variables,
      );

  static _Sql _idIn(Set<int> ids, {required bool negated}) => (
        sql: 'e.id ${negated ? 'NOT IN' : 'IN'} (${List.filled(ids.length, '?').join(', ')})',
        variables: [for (final id in ids) Variable(id)],
      );

  static _Sql _and(List<_Sql> parts) => (
        sql: '(${parts.map((p) => p.sql).join(' AND ')})',
        variables: [for (final p in parts) ...p.variables],
      );

  static _Sql _or(List<_Sql> parts) => parts.length == 1
      ? parts.single
      : (
          sql: '(${parts.map((p) => p.sql).join(' OR ')})',
          variables: [for (final p in parts) ...p.variables],
        );
}
