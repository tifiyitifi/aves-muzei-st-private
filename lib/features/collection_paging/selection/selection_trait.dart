import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';

/// One trait a marked view can be selected or deselected by, as a whole.
///
/// A trait carries both of its faces because a mark has to answer three
/// questions that must never disagree: how many rows it covers (a database
/// count), which rows a walk yields (the same predicate), and whether a visible
/// tile is highlighted (an in-memory test). [fragment] is the exact SQL of
/// [test], so the three stay one decision instead of three.
class SelectionTrait {
  /// SQL equivalent of [test] over the standard window aliases.
  final WindowFragment fragment;

  /// In-memory membership test, true exactly where [fragment] evaluates to `1`.
  final bool Function(AvesEntry entry) test;

  const new({required this.fragment, required this.test});

  /// The trait of a collection filter, or null when the filter has no SQL
  /// translation (the caller then keeps the legacy behaviour rather than
  /// deselecting a different set of rows).
  ///
  /// Reuses the one filter→SQL translation the view predicates use, and the
  /// filter's own in-memory test, so a trait can never disagree with the same
  /// filter used as a view — a reversed filter included.
  static SelectionTrait? fromFilter(CollectionFilter filter) {
    final fragment = filterTestFragment(filter);
    if (fragment == null) return null;
    return SelectionTrait(fragment: fragment, test: filter.test);
  }
}

/// One entry of a mark's trait history.
///
/// The history is append-only and ordered: for a row several traits cover, the
/// *last* op that covers it decides. Undoing an op is appending its opposite,
/// which leaves what the later ops mean untouched.
class SelectionTraitOp {
  final SelectionTrait trait;

  /// True when the op selects the trait's rows, false when it deselects them.
  final bool select;

  /// Localized description, resolved where the trait was picked (a section
  /// header's title, a filter's label), so the mark itself stays context-free.
  final String label;

  const new({required this.trait, required this.select, required this.label});
}
