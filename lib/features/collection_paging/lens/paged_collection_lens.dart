import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/catalog/paged_catalog_worker.dart';
import 'package:aves/features/collection_paging/lens/paged_bootstrap.dart';
import 'package:aves/features/collection_paging/lens/paged_lists.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/summary/paged_filter_summaries.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/features/collection_paging/windows/window_cache.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/events.dart';
import 'package:aves/model/source/location/location.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// One section's windowed state: lazy list plus the cache feeding it.
class _SectionState {
  final SectionHeader header;
  final SectionKey key;
  final PagedSectionList list;

  late final WindowCache<AvesEntry> cache;

  new({
    required this.header,
    required this.key,
    required this.list,
  });
}

/// A [CollectionLens] that materializes only the visible windows.
///
/// The grid, drawer, viewer and selection consume the exact same interface as
/// the legacy lens (`sortedEntries`, `sections`, `entryCount`, ...), backed by
/// `COUNT` + `GROUP BY` + `LIMIT/OFFSET` instead of a full in-memory list.
/// Unloaded positions hold a [SkeletonEntry]; the tile layer renders those as
/// shimmer, and selection expansion drops them.
///
/// Modes:
/// - paged: windows from the database (the default for large collections);
/// - morphed: provably small or explicitly legacy scopes behave exactly like
///   the legacy lens (display calls delegate to `super`);
/// - blocked: unsupported scopes on huge libraries show an empty grid with a
///   notice instead of crashing. Falling back to a full load would reintroduce
///   the very OOM this lens exists to prevent.
class PagedCollectionLens extends CollectionLens {
  /// Set when the current filters cannot be served from the database.
  bool _blocked = false;

  bool get pagedBlocked => _blocked;

  bool _morphed = false;

  bool _pagedActive = false;

  /// False for fixed-selection (viewer) copies, morphed and blocked states.
  bool get pagedActive => _pagedActive && !_blocked && !_morphed && fixedSelection == null;

  int _total = 0;
  List<_SectionState> _sectionStates = const [];
  PagedFlatList _flat = PagedFlatList(const []);

  int _reloadGen = 0;
  bool _reloading = false;
  bool _disposed = false;
  PagedFilterSummaries? _summaries;
  PagedCatalogWorker? _catalogWorker;
  final PagedCatalogWorker Function({required CollectionSource source}) _catalogWorkerFactory;
  final List<StreamSubscription> _pagedSubs = [];
  StreamSubscription<SettingsChangedEvent>? _layoutFactorSub;
  VoidCallback? _vaultsListener;

  new({
    required super.source,
    super.filters,
    super.id,
    super.fixedSort,
    super.fixedSelection,
    PagedCatalogWorker Function({required CollectionSource source})? catalogWorkerFactory,
  })  : _catalogWorkerFactory = catalogWorkerFactory ?? PagedCatalogWorker.new,
        super(listenToSource: false) {
    _pagedSubs.addAll([
      source.eventBus.on<EntryAddedEvent>().listen((_) => refresh()),
      source.eventBus.on<EntryRemovedEvent>().listen((_) => refresh()),
      source.eventBus.on<EntryMovedEvent>().listen((_) => refresh()),
      source.eventBus.on<EntryRefreshedEvent>().listen((_) => refresh()),
      source.eventBus.on<FilterVisibilityChangedEvent>().listen((_) => refresh()),
      source.eventBus.on<CatalogMetadataChangedEvent>().listen((_) => refresh()),
      source.eventBus.on<AddressMetadataChangedEvent>().listen((_) => refresh()),
    ]);
    _vaultsListener = refresh;
    vaults.lockStateChangeNotifier.addListener(_vaultsListener!);
    // The superclass already subscribed its own layout-factor handler, which
    // keeps the public factors current and rebuilds the legacy structures.
    // Ours only triggers a windowed reload; it skips morphed lenses because
    // the superclass handler alone is correct there.
    _layoutFactorSub = settings.updateStream.where(_isPagedLayoutFactorEvent).listen((_) {
      if (!_morphed) refresh();
    });
    if (fixedSelection == null) {
      refresh();
    } else {
      _installFixedSelection();
    }
  }

  // Mirrors the upstream layout-factor key set: any event that would reshape
  // the legacy lens reshapes the paged one. The keys themselves live in
  // `SettingKeys`; only the list shape is duplicated from
  // `CollectionLens._isLayoutFactorEvent`.
  static const _layoutFactorKeys = [
    SettingKeys.collectionBurstPatternsKey,
    SettingKeys.collectionSortFactorKey,
    SettingKeys.collectionSortReverseKey,
    SettingKeys.collectionSectionFactorKey,
    SettingKeys.calendarKey,
  ];

  static bool _isPagedLayoutFactorEvent(SettingsChangedEvent event) {
    if (_layoutFactorKeys.contains(event.key)) return true;
    return event.key.startsWith(SettingKeys.tileLayoutPrefixKey);
  }

  @override
  void dispose() {
    _disposed = true;
    _detachSummaries();
    _detachCatalogWorker();
    for (final sub in _pagedSubs) {
      sub.cancel();
    }
    _pagedSubs.clear();
    unawaited(_layoutFactorSub?.cancel());
    final vaultsListener = _vaultsListener;
    if (vaultsListener != null) {
      vaults.lockStateChangeNotifier.removeListener(vaultsListener);
      _vaultsListener = null;
    }
    final states = _sectionStates;
    _sectionStates = const [];
    for (final state in states) {
      state.list.skeleton.dispose();
    }
    super.dispose();
  }

  @override
  int get entryCount {
    final fixed = fixedSelection;
    if (fixed != null) return fixed.length;
    if (_morphed) return super.entryCount;
    return _total;
  }

  @override
  bool get isEmpty => entryCount == 0;

  @override
  List<AvesEntry> get sortedEntries {
    final fixed = fixedSelection;
    if (fixed != null) return fixed;
    if (_morphed) return super.sortedEntries;
    return _flat;
  }

  /// Loaded real entries in display order. Shared with viewer copies, which
  /// must never walk the lazy list.
  List<AvesEntry> get loadedEntries {
    final result = <AvesEntry>[];
    for (final state in _sectionStates) {
      final keys = state.list.loaded.keys.toList()..sort();
      for (final key in keys) {
        result.add(state.list.loaded[key]!);
      }
    }
    return result;
  }

  /// Live total for viewer copies.
  int get totalCount => _total;

  /// The live windowed list. Viewer copies read through it on every access so
  /// they track refreshes; they never mutate it.
  PagedFlatList get liveFlatList => _flat;

  /// False once disposed; viewer copies go empty instead of touching dead caches.
  bool get lensAlive => !_disposed;

  /// Kicks the windows around [globalIndex] (plus the cache's own prefetch
  /// neighbourhood) and waits for the drain, so a caller can then read rows
  /// synchronously. Never throws: a failed fetch simply leaves skeletons.
  Future<void> fillAround(int globalIndex) async {
    if (_disposed || _total == 0) return;
    final index = globalIndex.clamp(0, _total - 1);
    final (section, local) = _flat.locate(index);
    final cache = _sectionStates.firstWhereOrNull((s) => identical(s.list, section))?.cache;
    if (cache == null) return;
    await cache.ensureAround(local);
  }

  @override
  void refresh() {
    if (fixedSelection != null) {
      _installFixedSelection();
      notifyListeners();
      return;
    }
    if (_morphed) {
      super.refresh();
      return;
    }
    unawaited(_reload());
  }

  void _installFixedSelection() {
    final fixed = fixedSelection!;
    _total = fixed.length;
    _flat = PagedFlatList(const []);
    sections = Map.unmodifiable({const SectionKey(): fixed});
    notifyListeners();
  }

  Future<void> _reload() async {
    if (_reloading || _disposed || _morphed) return;
    _reloading = true;
    final gen = ++_reloadGen;
    try {
      await PagedBootstrap.ensure(source);
      if (!_current(gen)) return;

      // Steady-state MediaStore sync: one cheap generation query when quiet,
      // bounded change handling otherwise. New files appear without a restart.
      await PagedDiscoverer().syncIfChanged();
      if (!_current(gen)) return;

      var decision = await const CollectionEngineRouter().resolve(filters: filters);
      if (!_current(gen)) return;

      if (decision.total == 0 && await _isDatabaseEmpty()) {
        // Fresh database on an unseen library: bulk import, then re-resolve.
        // Skipped for legitimately empty scopes (e.g. an empty trash).
        await _initialImport(gen);
        if (!_current(gen)) return;
        decision = await const CollectionEngineRouter().resolve(filters: filters);
        if (!_current(gen)) return;
      }

      if (decision.route == CollectionRoute.legacy) {
        await _enterLegacy(decision, gen);
        return;
      }
      await _enterPaged(decision, gen);
    } catch (error, stack) {
      if (!_current(gen)) return;
      _log.e('paged reload failed', error, stack);
      _enterBlocked();
    } finally {
      _reloading = false;
    }
  }

  Future<bool> _isDatabaseEmpty() async {
    try {
      return await localMediaDb.countEntries() == 0;
    } catch (error, stack) {
      _log.w('paged emptiness probe failed', error, stack);
      return false;
    }
  }

  Future<void> _initialImport(int gen) async {
    source.state = SourceState.loading;
    source.setProgress(done: 0, total: 0);
    notifyListeners();
    try {
      final imported = await PagedDiscoverer().importAll(
        onProgress: (done) {
          if (_current(gen)) {
            source.setProgress(done: done, total: 0);
          }
        },
      );
      _log.d('paged bulk import complete: $imported rows');
    } catch (error, stack) {
      _log.e('paged bulk import failed', error, stack);
    }
  }

  bool _current(int gen) => gen == _reloadGen && !_disposed;

  /// Legacy path inside the paged lens: only taken when the whole library fits
  /// below the threshold (or the source is already fully loaded), so a full
  /// load is provably safe. Display calls delegate to `super` afterwards.
  Future<void> _enterLegacy(EngineDecision decision, int gen) async {
    if (source.loadedScope != CollectionSource.fullScope) {
      final full = await localMediaDb.countEntries();
      if (!_current(gen)) return;
      if (full >= collectionPagingPrefs.largeThreshold) {
        _enterBlocked();
        return;
      }
      await source.init(scope: CollectionSource.fullScope);
      if (!_current(gen)) return;
    }
    super.refresh();
    if (!_current(gen)) return;
    _detachSummaries();
    _detachCatalogWorker();
    _blocked = false;
    _morphed = true;
    _pagedActive = false;
    notifyListeners();
  }

  void _enterBlocked() {
    _blocked = true;
    _morphed = false;
    _pagedActive = false;
    _total = 0;
    _sectionStates = const [];
    _flat = PagedFlatList(const []);
    sections = Map.unmodifiable(const {});
    source.state = SourceState.ready;
    notifyListeners();
  }

  Future<void> _enterPaged(EngineDecision decision, int gen) async {
    final predicate = decision.predicate;
    if (predicate == null) {
      _enterBlocked();
      return;
    }
    final prefs = collectionPagingPrefs;
    await prefs.init();
    if (!_current(gen)) return;

    final grouping = _resolveGrouping();
    if (grouping == null) {
      _enterBlocked();
      return;
    }

    source.state = SourceState.loading;
    final sort = settings.getEffectiveCollectionSortFactor(filters);
    final reverse = settings.getEffectiveCollectionSortReverse(filters);
    final windowSize = prefs.windowSize;
    final prefetch = prefs.prefetchScreens;
    final total = await localMediaDb.countEntries(
      origin: predicate.origin,
      directory: predicate.directory,
      excludeTrashed: predicate.excludeTrashed,
      trashedOnly: predicate.trashedOnly,
    );
    if (!_current(gen)) return;

    final headers = await localMediaDb.loadSectionHeaders(
      origin: predicate.origin,
      directory: predicate.directory,
      excludeTrashed: predicate.excludeTrashed,
      trashedOnly: predicate.trashedOnly,
      grouping: grouping,
      reverse: reverse,
    );
    if (!_current(gen)) return;

    final cacheMaxWindows = 2 * (prefetch + 1) + 4;
    final states = <_SectionState>[];
    final lists = <SectionKey, PagedSectionList>{};
    for (final header in headers) {
      final key = _sectionKeyFor(header);
      final list = PagedSectionList(
        sectionKey: key,
        count: header.count,
        skeleton: _skeletonFor(header, key),
      );
      final range = _rangeFor(header);
      final state = _SectionState(header: header, key: key, list: list);
      state.cache = WindowCache<AvesEntry>(
        fetch: (windowIndex, limit, offset) => localMediaDb.loadEntryWindow(
          origin: predicate.origin,
          directory: predicate.directory,
          excludeTrashed: predicate.excludeTrashed,
          trashedOnly: predicate.trashedOnly,
          directoryEquals: range.directoryEquals,
          directoryEqualsNull: range.directoryEqualsNull,
          dateFromMillis: range.dateFromMillis,
          dateToMillis: range.dateToMillis,
          ratingEquals: range.ratingEquals,
          sort: sort,
          reverse: reverse,
          limit: limit,
          offset: offset,
        ),
        windowSize: windowSize,
        prefetchWindows: prefetch,
        maxWindows: cacheMaxWindows,
        onFilled: (windowIndex, rows) {
          if (!_current(gen)) return;
          final base = windowIndex * windowSize;
          for (var i = 0; i < rows.length; i++) {
            final entry = rows[i];
            state.list.loaded[base + i] = entry;
            state.list.idToLocal[entry.id] = base + i;
          }
          _reindexFlat();
          notifyListeners();
        },
        onEvicted: (windowIndex) {
          if (!_current(gen)) return;
          final base = windowIndex * windowSize;
          for (var i = 0; i < windowSize; i++) {
            final removed = state.list.loaded.remove(base + i);
            if (removed != null) {
              state.list.idToLocal.remove(removed.id);
              _flat.idToGlobal.remove(removed.id);
            }
          }
        },
      );
      list.cache = state.cache;
      states.add(state);
      lists[key] = list;
    }

    _total = total;
    _sectionStates = List.unmodifiable(states);
    _flat = PagedFlatList(List.unmodifiable(lists.values.toList()));
    sections = Map.unmodifiable(lists);
    _blocked = false;
    _morphed = false;
    _pagedActive = true;
    if (grouping == SectionGrouping.album) {
      PagedBootstrap.feedDirectories(source, headers);
    }
    _attachSummaries();
    if (!_current(gen)) return;
    // Eager albums on first entry; refreshes already-loaded domains (tags,
    // locations) whose rows may have changed. Never throws: a failed domain
    // stays unloaded and retries on next touch.
    await _summaries!.reload();
    if (!_current(gen)) return;
    // Backlog catalog runs behind the instant grid: the worker fills tags,
    // precise dates and countries in bounded chunks without blocking display.
    _attachCatalogWorker();
    unawaited(_runCatalogBacklog());
    source.state = SourceState.ready;
    notifyListeners();
  }

  void _attachSummaries() {
    _summaries ??= PagedFilterSummaries(
      source: source,
      hiddenFilters: () => settings.hiddenFilters,
      lockedVaultDirs: () => vaults.vaultDirectories.where(vaults.isLocked).toSet(),
    );
    source.summaries = _summaries;
  }

  void _detachSummaries() {
    source.summaries = null;
    _summaries?.dispose();
    _summaries = null;
  }

  void _attachCatalogWorker() {
    _catalogWorker ??= _catalogWorkerFactory(source: source);
  }

  Future<void> _runCatalogBacklog() async {
    final worker = _catalogWorker;
    if (worker == null || worker.isRunning) return;
    try {
      if (await localMediaDb.countUncatalogued() == 0) return;
    } catch (error, stack) {
      _log.w('paged catalog backlog probe failed', error, stack);
      return;
    }
    await worker.run();
  }

  void _detachCatalogWorker() {
    _catalogWorker?.stop();
    _catalogWorker = null;
  }

  /// Rebuilds the flat global-index map from the loaded section rows.
  void _reindexFlat() {
    _flat.idToGlobal.clear();
    var global = 0;
    for (final state in _sectionStates) {
      for (final local in state.list.loaded.keys) {
        _flat.idToGlobal[state.list.loaded[local]!.id] = global + local;
      }
      global += state.list.count;
    }
  }

  SectionKey _sectionKeyFor(SectionHeader header) {
    switch (header.grouping) {
      case SectionGrouping.album:
        return EntryAlbumSectionKey(header.directory);
      case SectionGrouping.month:
        return EntryDateSectionKey(year: header.year, month: header.month);
      case SectionGrouping.day:
        return EntryDateSectionKey(year: header.year, month: header.month, day: header.day);
      case SectionGrouping.rating:
        return EntryRatingSectionKey(header.rating ?? 0);
      case SectionGrouping.single:
        return const SectionKey();
    }
  }

  SkeletonEntry _skeletonFor(SectionHeader header, SectionKey key) {
    switch (header.grouping) {
      case SectionGrouping.album:
        return SkeletonEntry.forAlbum(header.directory, key as EntryAlbumSectionKey);
      case SectionGrouping.month:
        return SkeletonEntry.forMonth(header.year!, header.month!, key as EntryDateSectionKey);
      case SectionGrouping.day:
        return SkeletonEntry.forDay(header.year!, header.month!, header.day!, key as EntryDateSectionKey);
      case SectionGrouping.rating:
        return SkeletonEntry.forRating(header.rating ?? 0, key as EntryRatingSectionKey);
      case SectionGrouping.single:
        return SkeletonEntry.forSingle(key);
    }
  }

  /// SQL section predicate matching [header], mirroring the header's `GROUP BY`.
  ({String? directoryEquals, bool directoryEqualsNull, int? dateFromMillis, int? dateToMillis, int? ratingEquals}) _rangeFor(SectionHeader header) {
    switch (header.grouping) {
      case SectionGrouping.album:
        final dir = header.directory;
        return (directoryEquals: dir, directoryEqualsNull: dir == null, dateFromMillis: null, dateToMillis: null, ratingEquals: null);
      case SectionGrouping.month:
        final start = DateTime(header.year!, header.month!);
        final end = DateTime(header.year!, header.month! + 1);
        return (directoryEquals: null, directoryEqualsNull: false, dateFromMillis: start.millisecondsSinceEpoch, dateToMillis: end.millisecondsSinceEpoch, ratingEquals: null);
      case SectionGrouping.day:
        final start = DateTime(header.year!, header.month!, header.day!);
        final end = start.add(const Duration(days: 1));
        return (directoryEquals: null, directoryEqualsNull: false, dateFromMillis: start.millisecondsSinceEpoch, dateToMillis: end.millisecondsSinceEpoch, ratingEquals: null);
      case SectionGrouping.rating:
        return (directoryEquals: null, directoryEqualsNull: false, dateFromMillis: null, dateToMillis: null, ratingEquals: header.rating ?? 0);
      case SectionGrouping.single:
        return (directoryEquals: null, directoryEqualsNull: false, dateFromMillis: null, dateToMillis: null, ratingEquals: null);
    }
  }

  /// Maps the effective sort/section factors to a SQL grouping, or null when
  /// the combination needs the legacy path.
  SectionGrouping? _resolveGrouping() {
    if (fixedSort) return SectionGrouping.single;
    // Calendar synthesis and mosaic measuring need realized entries.
    if (tileLayout == TileLayout.calendar || tileLayout == TileLayout.mosaic) return null;
    if (calendar != ACalendar.gregorian) {
      if (sectionFactor == EntrySectionFactor.month || sectionFactor == EntrySectionFactor.day) return null;
    }
    switch (sortFactor) {
      case SortFactor.date:
        return switch (sectionFactor) {
          EntrySectionFactor.album => SectionGrouping.album,
          EntrySectionFactor.month => SectionGrouping.month,
          EntrySectionFactor.day => SectionGrouping.day,
          EntrySectionFactor.none => SectionGrouping.single,
          EntrySectionFactor.name || EntrySectionFactor.rating => null,
        };
      case SortFactor.albumItemName:
      case SortFactor.path:
        return SectionGrouping.album;
      case SortFactor.rating:
        return SectionGrouping.rating;
      case SortFactor.size:
      case SortFactor.duration:
        return SectionGrouping.single;
      case SortFactor.chipName:
      case SortFactor.count:
        return null;
    }
  }

  @override
  CollectionLens copyWith({
    CollectionSource? source,
    Set<CollectionFilter>? filters,
    bool? listenToSource,
    List<AvesEntry>? fixedSelection,
  }) {
    if (_morphed && fixedSelection == null) {
      return super.copyWith(source: source, filters: filters, fixedSelection: fixedSelection, listenToSource: listenToSource);
    }
    // Viewer copies share the live windows instead of snapshotting loaded
    // rows, so swiping past the loaded neighbourhood keeps resolving.
    if (fixedSelection == null && _pagedActive && !_blocked) {
      return PagedViewerCopy(parent: this);
    }
    // The paged lens manages its own subscriptions; viewer copies are inert.
    fixedSelection ??= loadedEntries;
    return PagedCollectionLens(
      source: source ?? this.source,
      filters: filters ?? this.filters,
      id: id,
      fixedSort: fixedSort,
      fixedSelection: fixedSelection,
    );
  }
}
