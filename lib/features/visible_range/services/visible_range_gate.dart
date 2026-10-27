import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:flutter/foundation.dart';

/// A browsing-only overlay contributed by the wallpaper page.
///
/// The gallery range and a wallpaper group's range are independent data sets.
/// The group one is only applied while the wallpaper page is open, and there it
/// joins the gallery range instead of replacing it. Suspending the gallery range
/// is a temporary view choice (the page restores it on leaving), never a write.
@immutable
class VisibleRangeBrowsingOverlay {
  /// Resolved filter of the group the wallpaper page shows, or null for group 0.
  final CollectionFilter? groupFilter;

  /// Whether the gallery range is temporarily ignored while the page is open.
  final bool gallerySuspended;

  const new({this.groupFilter, this.gallerySuspended = false});
}

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

  /// The wallpaper page's browsing overlay, active only while that page is open.
  ///
  /// The live wallpaper never reads this gate: it uses the saved group range
  /// through `wallpaperMediaSetFilter`, so gallery browsing can never narrow the
  /// wallpaper result.
  static VisibleRangeBrowsingOverlay? overlay;

  static VisibleRangeController get _controller => debugController ?? visibleRangeController;

  /// The resolved browsing filter: the gallery range, the wallpaper page's
  /// group range, or their intersection when the page is open.
  static CollectionFilter? get filter {
    final current = overlay;
    final gallery = current != null && current.gallerySuspended ? null : _controller.galleryFilter;
    final group = current?.groupFilter;
    if (gallery == null) return group;
    if (group == null) return gallery;
    return SetAndFilter({gallery, group});
  }

  /// The gallery range alone, ignoring the wallpaper page's overlay.
  static CollectionFilter? get galleryFilter => _controller.galleryFilter;

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

  /// Whether [entry] is inside the current browsing range.
  static bool accepts(AvesEntry entry) {
    final range = filter;
    return range == null || range.test(entry);
  }
}
