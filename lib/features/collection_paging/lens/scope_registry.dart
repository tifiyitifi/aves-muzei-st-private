import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:collection/collection.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// The view a route asked for: its filters, canonicalised so two routes naming
/// the same filters in a different order are the same scope.
///
/// The filters are the scope's identity: an album is never served by the media
/// set's window (or the other way round), and another album is another view.
String scopeKeyOf(Set<CollectionFilter?>? filters) {
  final sorted = List<CollectionFilter>.of((filters ?? const {}).nonNulls)..sort();
  return sorted.map((v) => v.toJsonString()).join('|');
}

Set<CollectionFilter> _routeFiltersOf(Set<CollectionFilter?>? filters) => (filters ?? const {}).nonNulls.toSet();

class _ScopeEntry {
  final String key;
  final Set<CollectionFilter> routeFilters;
  final PagedCollectionLens lens;

  /// How many mounted pages show this view. A lens is only parked and only
  /// evicted at zero, which also keeps a lens alive while the next route's page
  /// mounts before this one is disposed.
  int refCount = 0;

  int lastUsed = 0;

  new({
    required this.key,
    required this.routeFilters,
    required this.lens,
    required this.lastUsed,
  });
}

/// Keeps a view alive across navigation, so coming back to it is a repaint
/// instead of a database round trip.
///
/// Every scope switch used to dispose the page's lens and resolve the next one
/// from scratch — the catalogued dates, the counts, the section headers, the
/// first window — which the grid could only answer with a loading body. Here the
/// lens, with its published window, its filters and its summaries, outlives the
/// page that showed it.
///
/// Memory is bounded by [retainedScopes]: the scope the app started on (the home
/// collection the drawer and the bottom bar lead back to) is pinned, and the most
/// recently used other scope rides along. Opening yet another scope replaces
/// that one, which is exactly what discards an album's state when the next album
/// is opened.
class ScopeRegistry {
  /// Views kept alive at the same time, the pinned home included.
  static const int retainedScopes = 2;

  final Map<String, _ScopeEntry> _entries = {};

  int _clock = 0;

  /// The scope the app started on: the way back to the library.
  String? _homeKey;

  String? _activeKey;

  /// The lens the mounted page shows, if any.
  PagedCollectionLens? get active => _entries[_activeKey]?.lens;

  /// How many views are retained, for diagnostics and tests.
  int get scopeCount => _entries.length;

  /// The view for [filters], resolved if this is the first time it is shown.
  ///
  /// A retained view comes back as it was: its window is already published, so
  /// the page paints it on its first frame and no loading body appears.
  PagedCollectionLens acquire({
    required CollectionSource source,
    Set<CollectionFilter?>? filters,
  }) {
    final entry = _obtain(source: source, filters: filters);
    entry.refCount++;
    _activate(entry);
    _evict();
    return entry.lens;
  }

  /// The page showing [lens] is gone. The view is parked, not disposed: it is
  /// what the next visit paints from.
  void release(PagedCollectionLens lens) {
    final entry = _entries.values.firstWhereOrNull((v) => identical(v.lens, lens));
    if (entry == null) return;
    if (entry.refCount > 0) entry.refCount--;
    if (entry.refCount > 0) return;
    if (entry.key == _activeKey) {
      _activeKey = null;
      lens.setActive(false);
    }
    _evict();
    _log.d('scope parked ${entry.key}, retained=${_entries.length}');
  }

  /// Starts a view's first resolve before its page is on screen.
  ///
  /// A tap on a collection destination is the decision to show it; resolving
  /// while the route transition runs is what keeps the loading body out of
  /// sight on the first visit. Returns the view it opened, or the retained one.
  PagedCollectionLens? prewarm({
    required CollectionSource source,
    Set<CollectionFilter?>? filters,
  }) {
    final key = scopeKeyOf(filters);
    if (_entries.containsKey(key)) return _entries[key]?.lens;
    final entry = _obtain(source: source, filters: filters);
    _evict();
    return entry.lens;
  }

  /// Forgets every retained view, disposing its lens. For tests and a library
  /// reset; the app itself keeps them for its whole life.
  void reset() {
    for (final entry in _entries.values.toList()) {
      entry.lens.dispose();
    }
    _entries.clear();
    _activeKey = null;
    _homeKey = null;
    _clock = 0;
  }

  _ScopeEntry _obtain({
    required CollectionSource source,
    Set<CollectionFilter?>? filters,
  }) {
    final key = scopeKeyOf(filters);
    final existing = _entries[key];
    if (existing != null) {
      _applyRouteFilters(existing);
      existing.lastUsed = ++_clock;
      return existing;
    }
    final routeFilters = _routeFiltersOf(filters);
    final lens = PagedCollectionLens(source: source, filters: routeFilters);
    // Nothing shows it yet: a resolve that lands before its page does must not
    // drive the state of the page that is on screen.
    lens.setActive(false);
    final entry = _ScopeEntry(
      key: key,
      routeFilters: routeFilters,
      lens: lens,
      lastUsed: ++_clock,
    );
    _entries[key] = entry;
    _homeKey ??= key;
    _log.d('scope opened $key (${routeFilters.length} filters), retained=${_entries.length}');
    return entry;
  }

  void _activate(_ScopeEntry entry) {
    for (final other in _entries.values) {
      if (!identical(other, entry) && other.lens.isActive) other.lens.setActive(false);
    }
    _activeKey = entry.key;
    entry.lastUsed = ++_clock;
    entry.lens.setActive(true);
  }

  /// Re-applies the filters the route named.
  ///
  /// The user can drop a scope's own chip while inside it — that is what the
  /// clear action does — and the scope stays that scope, so the next visit
  /// restores it. In the common case nothing changes, which is what lets a
  /// returning view keep its window instead of re-resolving it.
  void _applyRouteFilters(_ScopeEntry entry) {
    final target = {...entry.lens.filters, ...entry.routeFilters};
    if (const SetEquality().equals(entry.lens.filters, target)) return;
    entry.lens.setFilters(target);
  }

  /// Drops the least recently used view that nothing is showing.
  ///
  /// A view with a mounted page, the pinned home, and the view being opened are
  /// never victims, so the count can exceed [retainedScopes] for the one frame a
  /// route transition keeps two pages alive.
  void _evict() {
    while (_entries.length > retainedScopes) {
      _ScopeEntry? victim;
      for (final entry in _entries.values) {
        if (entry.key == _homeKey) continue;
        if (entry.key == _activeKey) continue;
        if (entry.refCount > 0) continue;
        if (victim == null || entry.lastUsed < victim.lastUsed) victim = entry;
      }
      if (victim == null) return;
      _entries.remove(victim.key);
      victim.lens.dispose();
      _log.d('scope dropped ${victim.key}, retained=${_entries.length}');
    }
  }
}

/// The app-wide scope registry (same singleton style as `collectionPagingPrefs`).
final ScopeRegistry scopeRegistry = ScopeRegistry();
