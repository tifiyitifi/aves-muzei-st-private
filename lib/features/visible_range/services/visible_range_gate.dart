import 'dart:async';

import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:flutter/foundation.dart';

/// A browsing-only overlay contributed by the wallpaper group page.
///
/// The gallery range and a wallpaper group's range are independent data sets.
/// The group one follows the group the wallpaper page is showing, and it joins
/// the gallery range instead of replacing it. Suspending the gallery range is a
/// temporary view choice (the page restores it on leaving), never a write.
@immutable
class VisibleRangeBrowsingOverlay {
  /// Resolved filter of the group the wallpaper page shows, or null for group 0.
  final CollectionFilter? groupFilter;

  /// Whether the gallery range is temporarily ignored while the page is open.
  final bool gallerySuspended;

  const new({this.groupFilter, this.gallerySuspended = false});

  /// Value equality keeps a page re-publishing the same scope from invalidating
  /// every browsing cache.
  @override
  bool operator ==(Object other) => other is VisibleRangeBrowsingOverlay && other.groupFilter == groupFilter && other.gallerySuspended == gallerySuspended;

  @override
  int get hashCode => Object.hash(groupFilter, gallerySuspended);
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

  /// The wallpaper page's browsing overlay.
  ///
  /// It follows the group the page shows and lives exactly as long as the page:
  /// the page publishes it while open (and any page pushed over it keeps it), and
  /// drops it when closed, so the rest of the app returns to the gallery range.
  /// It is in-memory only, so a process restart returns to the gallery range
  /// alone. Selecting group 0 clears it as well.
  ///
  /// The live wallpaper never reads this gate: it uses the saved group range
  /// through `wallpaperMediaSetFilter`, so gallery browsing can never narrow the
  /// wallpaper result.
  static final ValueNotifier<VisibleRangeBrowsingOverlay?> _overlay = ValueNotifier(null);

  /// Notifies when [overlay] changes.
  ///
  /// The paged and summary paths re-resolve on `FilterVisibilityChangedEvent`,
  /// but the legacy in-memory path caches `visibleEntries` and every filter
  /// summary derived from it. A source subscribes here to drop those caches, the
  /// same way it listens to the gallery controller.
  static ValueListenable<VisibleRangeBrowsingOverlay?> get overlayListenable => _overlay;

  static VisibleRangeBrowsingOverlay? get overlay => _overlay.value;

  static set overlay(VisibleRangeBrowsingOverlay? value) => _overlay.value = value;

  /// Stands for "no page owns the overlay", so a release can be a no-op without
  /// a nullable comparison against a token someone else holds.
  static final Object _unowned = Object();

  /// Identifies the page currently allowed to publish or release the overlay.
  ///
  /// Comparing values is not enough: a replacement page often publishes the very
  /// same group, and the notifier keeps the older, equal instance. An identity
  /// check would then let the closed page clear the new page's scope. The token
  /// is therefore per page, not per publish.
  static Object _overlayOwner = _unowned;

  /// Claims the overlay for a page and publishes its first scope.
  ///
  /// The returned token is the only thing that page may pass back to
  /// [releaseWallpaperScope]. Claiming while another page owns it takes over:
  /// the newest page is always the one describing the screen.
  static Object claimWallpaperScope(VisibleRangeBrowsingOverlay? value) {
    final owner = Object();
    _overlayOwner = owner;
    overlay = value;
    return owner;
  }

  /// Publishes the scope of the page that owns the overlay.
  ///
  /// Returns false when a newer page has taken over, in which case the caller's
  /// group no longer describes the screen and must not overwrite it.
  static bool publishWallpaperScope(Object owner, VisibleRangeBrowsingOverlay? value) {
    if (!identical(_overlayOwner, owner)) return false;
    overlay = value;
    return true;
  }

  /// Releases the overlay a page owned, without touching a newer page's scope.
  ///
  /// `State.dispose` runs while the framework finalizes the tree: notifying
  /// listeners there throws "setState() called when widget tree was locked" and
  /// breaks every `ListenableBuilder` in the chain, so the clear is deferred to
  /// a microtask. The future completes with whether this release applied.
  static Future<bool> releaseWallpaperScope(Object? owner) {
    if (owner == null) return Future.value(false);
    final completer = Completer<bool>();
    scheduleMicrotask(() {
      if (!identical(_overlayOwner, owner)) {
        completer.complete(false);
        return;
      }
      _overlayOwner = _unowned;
      overlay = null;
      completer.complete(true);
    });
    return completer.future;
  }

  /// Replaces the overlay with the group scope alone, dropping the page-local
  /// gallery suspension.
  ///
  /// [groupFilter] is the resolved filter of the group the page was showing, or
  /// null for group 0. Group 0 clears the overlay instead of keeping an empty
  /// one, so browsing falls back to the gallery range alone.
  static void setWallpaperScope(CollectionFilter? groupFilter) {
    overlay = groupFilter == null ? null : VisibleRangeBrowsingOverlay(groupFilter: groupFilter);
  }

  /// Temporarily stops (or resumes) applying the gallery range to browsing.
  ///
  /// The choice belongs to the overlay, not to a page: the wallpaper page and
  /// every surface pushed over it (the media set, the strip explaining an empty
  /// one) must flip the same switch, or each would keep its own copy and the
  /// collection would not re-resolve where the user tapped.
  ///
  /// It never writes the range: dropping the overlay restores it.
  static void setGallerySuspended(bool suspended) {
    final current = overlay;
    if (current == null) {
      // No wallpaper scope is published, so there is no group to browse: the
      // gallery range alone is what browsing means, and there is nothing to
      // suspend it in favour of.
      return;
    }
    if (current.gallerySuspended == suspended) return;
    overlay = VisibleRangeBrowsingOverlay(groupFilter: current.groupFilter, gallerySuspended: suspended);
  }

  /// Whether the gallery range currently restricts browsing.
  static bool get galleryRestricted => _controller.gallery.isRestricted;

  static VisibleRangeController get _controller => debugController ?? visibleRangeController;

  /// The resolved browsing filter: the gallery range, the wallpaper scope's
  /// group range, or their intersection.
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
