import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:collection/collection.dart';

/// Whether [filters] is a view a bottom-bar destination declares itself.
///
/// Video, favourites or an album pinned to the bar are their own destinations:
/// their views belong to them, so they must never write the media-set slot (and
/// visiting one must not make the media-set tab open it afterwards).
bool isDestinationView(Set<CollectionFilter> filters, Iterable<Set<CollectionFilter>?> destinationFilters) {
  return destinationFilters.nonNulls.any((v) => const SetEquality().equals(v, filters));
}

/// Whether a collection view that just mounted may write the media-set slot.
///
/// Two kinds of view must not: one a bottom-bar destination owns (see
/// [isDestinationView]), and one that is its own destination everywhere else.
/// The bin is the latter — it is a drawer page even though no bar item declares
/// it, and writing the slot there made the media-library item reopen the trash.
bool shouldNoteMediaSet(Set<CollectionFilter> filters, Iterable<Set<CollectionFilter>?> destinationFilters) {
  if (filters.contains(TrashFilter.instance)) return false;
  return !isDestinationView(filters, destinationFilters);
}

/// The collection view the media-set destination last showed.
///
/// The bottom bar's collection item declares no filters, so it used to always
/// open the whole library: after opening an album from the albums page, tapping
/// the tab reset the filters instead of returning to the album the user was in.
/// The tab is a slot that remembers its view. A view a nav item names itself
/// (video, favourites, an album pinned to the bar) belongs to that item and is
/// never written here, so it cannot hijack the slot either.
///
/// The view can drop the filters it was opened with (the clear action at the end
/// of the filter row), which is why the current filters are read live rather than
/// copied: a tab that reset to the whole library must reopen the whole library,
/// not resurrect the album behind the user's back.
class MediaSetTab {
  /// The filters the view was opened with: its scope identity, stable while the
  /// user adds or drops chips inside it.
  Set<CollectionFilter>? _routeFilters;

  /// The filters the view holds now, so a cleared view reads as cleared.
  Set<CollectionFilter> Function()? _currentFilters;

  /// The filters the media-set destination should open, or null when the slot has
  /// not shown anything yet (a cold start shows the whole library).
  Set<CollectionFilter>? get filters {
    final routeFilters = _routeFilters;
    if (routeFilters == null) return null;
    final currentFilters = _currentFilters?.call();
    if (currentFilters != null && !routeFilters.every(currentFilters.contains)) return const <CollectionFilter>{};
    return routeFilters;
  }

  /// The filters the view holds now, even when the user emptied it.
  ///
  /// [filters] is the scope identity a destination reopens; this is the live
  /// set a caller that wants to snapshot the user's edits after they leave the
  /// view must read.
  Set<CollectionFilter>? get currentFilters => _currentFilters?.call() ?? _routeFilters;

  /// Remembers the collection view that just mounted under the media-set slot.
  void note({
    required Set<CollectionFilter> routeFilters,
    required Set<CollectionFilter> Function() currentFilters,
  }) {
    _routeFilters = {...routeFilters};
    _currentFilters = currentFilters;
  }

  /// Forgets the slot, as if nothing had been shown yet.
  void clear() {
    _routeFilters = null;
    _currentFilters = null;
  }
}

/// The app-wide media-set slot (same singleton style as `scopeRegistry`).
final MediaSetTab mediaSetTab = MediaSetTab();
