import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:flutter/foundation.dart';

/// The single seam between the current gallery visible range and every browsing
/// path.
///
/// All three collection paths (paged predicate, summary query, legacy in-memory
/// scan) ask here instead of each deciding on its own, so a range can never be
/// enforced in one surface and forgotten in another.
abstract final class VisibleRangeGate {
  /// Test-only replacement for the app-wide controller, whose database is fixed
  /// at first initialization.
  @visibleForTesting
  static VisibleRangeController? debugController;

  static VisibleRangeController get _controller => debugController ?? visibleRangeController;

  /// The resolved range filter, or null for 「不限」.
  static CollectionFilter? get filter => _controller.galleryFilter;

  /// Augments a view's filters with the current range.
  ///
  /// Returning the same set when unrestricted keeps every caller's existing
  /// identity checks intact.
  static Set<CollectionFilter> apply(Set<CollectionFilter> filters) {
    // The recycle bin is a management surface, not browsing: its contents must
    // stay visible so the user can restore or empty them.
    if (filters.any((filter) => filter is TrashFilter)) return filters;
    final range = filter;
    if (range == null) return filters;
    return {...filters, range};
  }

  /// The complement of the range, for summary queries that model the range as
  /// "entries to exclude" so counts, covers and lists agree with browsing.
  static CollectionFilter? get summaryExclusion => filter?.reverse();

  /// Hidden filters plus the range complement, for `buildSummaryExclusion`.
  static Set<CollectionFilter> augmentHidden(Set<CollectionFilter> hidden) {
    final exclusion = summaryExclusion;
    if (exclusion == null) return hidden;
    return {...hidden, exclusion};
  }

  /// Whether [entry] is inside the current gallery visible range.
  static bool accepts(AvesEntry entry) {
    final range = filter;
    return range == null || range.test(entry);
  }
}
