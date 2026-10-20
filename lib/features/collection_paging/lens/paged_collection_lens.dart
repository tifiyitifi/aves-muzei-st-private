import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/catalog/catalog_prompt.dart';
import 'package:aves/features/collection_paging/catalog/catalog_service.dart';
import 'package:aves/features/collection_paging/catalog/paged_catalog_worker.dart';
import 'package:aves/features/collection_paging/import/import_rows.dart';
import 'package:aves/features/collection_paging/lens/paged_bootstrap.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/lens/paged_lists.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/selection/declared_entry_feed.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/features/collection_paging/selection/selection_trait.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/features/collection_paging/summary/paged_filter_summaries.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/features/collection_paging/windows/window_cache.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/locale/calendar/calendar_utils.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/events.dart';
import 'package:aves/model/source/location/location.dart';
import 'package:aves/model/source/location/place.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
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

  /// Rows across the whole library, for the `view / library` count line. The
  /// view total counts what the filters keep; this is the denominator.
  int _libraryTotal = 0;

  /// Whether the one-time import is still writing rows for this lens.
  ///
  /// Distinct from the source state: the source must stay in `loading` while
  /// this is true so the app bar keeps saying the library is being organized,
  /// even after the first windows resolved.
  bool _importingRows = false;

  /// Whether the grid has already been re-resolved once mid-import.
  ///
  /// The first resolve only sees the first batch; a huge library would otherwise
  /// show that batch until the whole import ends.
  bool _grewDuringImport = false;

  /// Listener for an import started by another surface, when this lens joined
  /// it instead of scanning again.
  void Function()? _externalImportListener;

  int _reloadGen = 0;
  bool _reloading = false;

  /// Coalesces the in-place metadata patches: a sweep flushes every 50 rows,
  /// and one patch per flush would still rebuild the grid hundreds of times.
  Timer? _metadataPatchTimer;
  bool _patchingMetadata = false;
  bool _disposed = false;
  final Completer<void> _ready = Completer<void>();

  /// Pending wait on a load this lens did not start (see [_awaitInFlightLoad]).
  Completer<void>? _inFlightLoadWait;
  VoidCallback? _inFlightLoadListener;

  /// Completes once the first load resolved (paged, morphed or blocked).
  /// Callers that must know which path was taken (the paged slideshow) await
  /// this instead of polling.
  Future<void> get ready => _ready.future;

  PagedFilterSummaries? _summaries;
  PagedCatalogWorker? _catalogWorker;
  final PagedCatalogWorker Function({required CollectionSource source}) _catalogWorkerFactory;
  final List<StreamSubscription> _pagedSubs = [];

  /// View-specific atoms appended to the compiled filter predicate (e.g. the
  /// slideshow's video exclusion, which is not one of the collection's filters
  /// but still defines which rows the view contains).
  final List<WindowFragment> _extraFragments;

  /// Whether the view folds each stack into the single tile it shows.
  final bool _stackEntries;

  StreamSubscription<SettingsChangedEvent>? _layoutFactorSub;
  VoidCallback? _vaultsListener;

  new({
    required super.source,
    super.filters,
    super.id,
    super.fixedSort,
    super.fixedSelection,
    PagedCatalogWorker Function({required CollectionSource source})? catalogWorkerFactory,
    bool stackEntries = true,
    List<WindowFragment> extraFragments = const [],
  })  : _catalogWorkerFactory = catalogWorkerFactory ?? PagedCatalogWorker.new,
        _stackEntries = stackEntries,
        _extraFragments = extraFragments,
        super(listenToSource: false) {
    _pagedSubs.addAll([
      source.eventBus.on<EntryAddedEvent>().listen((_) => refresh()),
      source.eventBus.on<EntryRemovedEvent>().listen((_) => refresh()),
      source.eventBus.on<EntryMovedEvent>().listen((_) => refresh()),
      source.eventBus.on<EntryRefreshedEvent>().listen((_) => refresh()),
      source.eventBus.on<FilterVisibilityChangedEvent>().listen((_) => refresh()),
      // Cataloguing and locating change row *content*, not which rows the view
      // holds: patch the tiles already on screen instead of re-resolving. A
      // full reload here rebuilt every section into skeletons on each 50-row
      // flush, which is constant flicker while a large backlog is swept.
      source.eventBus.on<CatalogMetadataChangedEvent>().listen((_) => _scheduleMetadataPatch()),
      source.eventBus.on<AddressMetadataChangedEvent>().listen((_) => _scheduleMetadataPatch()),
      // The locations domain loads when the user opens a places surface;
      // lazily backfill fine addresses then, instead of geocoding a huge
      // library up front.
      source.eventBus.on<PlacesChangedEvent>().listen((_) => _runPlacesBacklog()),
    ]);
    _vaultsListener = refresh;
    vaults.lockStateChangeNotifier.addListener(_vaultsListener!);
    // The superclass already subscribed its own layout-factor handler, which
    // keeps the public factors current and rebuilds the legacy structures.
    // Ours only triggers a windowed reload; it skips morphed lenses because
    // the superclass handler alone is correct there.
    _layoutFactorSub = settings.updateStream.where(_isPagedLayoutFactorEvent).listen((event) {
      if (event.key == SettingKeys.collectionBurstPatternsKey) {
        // The stored burst keys are derived from the patterns, so the index is
        // rebuilt in the background and the view refreshes again once it lands.
        unawaited(_rebuildStackIndex());
      }
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
    _cancelInFlightLoadWait();
    _metadataPatchTimer?.cancel();
    _metadataPatchTimer = null;
    final importListener = _externalImportListener;
    if (importListener != null) {
      pagedImportStatus.removeListener(importListener);
      _externalImportListener = null;
    }
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

  /// Rows in the whole library, or the view total when it cannot be known.
  ///
  /// The app bar shows the pair while the view is narrower than the library
  /// (a filter, or rows still being imported), so the denominator is always
  /// visible rather than implied.
  int get libraryEntryCount => _libraryTotal > 0 ? _libraryTotal : entryCount;

  /// Whether this lens is still importing rows into an empty database.
  bool get importingRows => _importingRows;

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
  List<AvesEntry> get loadedEntries => [for (final state in _sectionStates) ...state.list.loadedItems];

  /// The scope this view declares, for a whole-view selection.
  ///
  /// Null when the view cannot declare one: not paged, or no SQL predicate.
  SelectionScope? get selectionScope {
    final tiles = _pagedPredicate;
    final entries = _pagedEntryPredicate;
    if (!pagedActive || tiles == null || entries == null) return null;
    return SelectionScope(tiles: tiles, entries: entries, dayRows: _pagedDayRows);
  }

  /// A mark over this whole view, or null when the view cannot declare one.
  ///
  /// Both counts are seeded with the view's own totals, so the app bar and an
  /// action's dialogs are right before the database confirms them.
  CollectionSelectionMark? newSelectionMark() {
    final scope = selectionScope;
    if (scope == null) return null;
    return CollectionSelectionMark(scope: scope, count: _total, expandedCount: _entryTotal);
  }

  /// The feed a mark resolves to on this view, or null when the view cannot
  /// declare one.
  ///
  /// The predicate and the counts are read once, here: the feed walks a frozen
  /// scope, so a file added while the action runs is not swept in even though it
  /// matches the same mark.
  DeclaredEntryFeed? declaredFeed(CollectionSelectionMark mark) {
    if (selectionScope == null) return null;
    return DeclaredEntryFeed(
      mark: mark,
      tilePredicate: mark.tilePredicate,
      tileCount: mark.walkCount,
      count: mark.expandedCount,
      stackEntries: _stackEntries,
    );
  }

  /// The feed an action that covers the view itself resolves to ("empty the
  /// bin"), or null when the view cannot declare one.
  ///
  /// Nothing is unmarked: the action targets the whole scope rather than a
  /// selection, and the loaded neighbourhood would leave the rest behind.
  DeclaredEntryFeed? wholeViewFeed() {
    final scope = selectionScope;
    if (scope == null) return null;
    final mark = CollectionSelectionMark(scope: scope, count: _total, expandedCount: _entryTotal);
    return DeclaredEntryFeed(
      mark: mark,
      tilePredicate: mark.tilePredicate,
      tileCount: mark.walkCount,
      count: mark.expandedCount,
      stackEntries: _stackEntries,
    );
  }

  /// The trait a section header stands for, or null when the section has no
  /// exact trait (the caller then keeps the legacy loaded-rows behaviour).
  ///
  /// Every kind compiles to the rows the section's own window selects, so
  /// deselecting a section from its header removes exactly what it shows: an
  /// album is its `directory` (the `IS NULL` bucket included), a rating is the
  /// coalesced rating column, and a date section is the local range of the very
  /// date expression the grouping uses.
  SelectionTrait? sectionTrait(SectionKey key) {
    switch (key) {
      case EntryAlbumSectionKey(directory: final directory):
        if (directory == null) {
          // The bucket of entries with no directory: the grouping key is NULL
          // itself, and no album filter can name it.
          return SelectionTrait(
            fragment: (sql: 'e.directory IS NULL', variables: const [], requires: const {}),
            test: (entry) => entry.directory == null,
          );
        }
        return SelectionTrait.fromFilter(StoredAlbumFilter(directory, null));
      case EntryRatingSectionKey(rating: final rating):
        return SelectionTrait.fromFilter(RatingFilter(rating));
      case EntryDateSectionKey(year: final year, month: final month, day: final day):
        final range = _dateSectionRange(year: year, month: month, day: day);
        if (range == null) return null;
        final (from, to) = range;
        // The calendar projection groups days that all carry a usable date;
        // every other date section groups on the epoch fallback, which files an
        // entry without any date under the first month of 1970.
        final requiresDate = _pagedDayRows;
        return SelectionTrait(
          fragment: (
            sql: '($bestDateExpression >= ? AND $bestDateExpression < ?)',
            variables: [Variable(from), Variable(to)],
            requires: const {WindowTable.dateTaken},
          ),
          test: (entry) {
            final bestDate = entry.bestDate;
            if (requiresDate && bestDate == null) return false;
            // An entry with no usable date has the epoch fallback in SQL too.
            final millis = bestDate?.millisecondsSinceEpoch ?? 0;
            return millis >= from && millis < to;
          },
        );
      default:
        return null;
    }
  }

  /// The half-open local-time millisecond range of a date section, or null when
  /// the section key names no date.
  static (int, int)? _dateSectionRange({required int? year, required int? month, required int? day}) {
    if (year == null) return null;
    final from = DateTime(year, month ?? 1, day ?? 1);
    final to = day != null
        ? DateTime(year, month ?? 1, day + 1)
        : month != null
            ? DateTime(year, month + 1)
            : DateTime(year + 1);
    return (from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
  }

  /// The ratios the mosaic layout packs [key] with, or null while they load.
  ///
  /// Read by `PagedMosaicSectionLayoutBuilder` through the layout provider.
  List<double>? mosaicRatios(SectionKey key) => _mosaicRatios[key];

  /// Live total for viewer copies.
  int get totalCount => _total;

  /// The predicate/sort the current paged view resolved to; null until paged.
  CollectionWindowPredicate? _pagedPredicate;

  /// The same view with stacks *expanded*: the rows a selection covers.
  ///
  /// Equal to [_pagedPredicate] unless the view collapses stacks, in which case
  /// it also holds the members a tile hides — the rows the legacy selection
  /// counted and an action touched.
  CollectionWindowPredicate? _pagedEntryPredicate;

  /// Rows the view expands to, stack members included; [_total] counts tiles.
  int _entryTotal = 0;

  SortFactor _pagedSort = SortFactor.date;
  bool _pagedReverse = false;

  /// True when the current paged view projects one row per day (the calendar
  /// layout), so positions, totals and index lookups count days.
  bool _pagedDayRows = false;

  /// True when the layout shows one row per day under month sections.
  bool get _dayRows => !fixedSort && tileLayout == TileLayout.calendar;

  /// True when the layout packs sections from a measured ratio channel.
  bool get _mosaic => !fixedSort && tileLayout == TileLayout.mosaic;

  /// Display ratios per section, for the mosaic packing. Cleared on every
  /// resolve; a section is absent until its channel lands.
  final Map<SectionKey, List<double>> _mosaicRatios = {};

  /// Global index of the entry with [id] in the current view, or -1 when the
  /// view is not paged (the legacy list answers in memory) or [id] is not in
  /// the view.
  ///
  /// Resolved with the database's own ordering, so a viewer can open on an
  /// entry that is not in any loaded window.
  Future<int> indexOfId(int id) async {
    final predicate = _pagedPredicate;
    if (!pagedActive || predicate == null) {
      final index = sortedEntries.indexWhere((entry) => entry.id == id);
      return index;
    }
    try {
      // The calendar projection counts days, not rows.
      if (_pagedDayRows) {
        return await localMediaDb.countDaysBefore(predicate: predicate, id: id, reverse: _pagedReverse);
      }
      return await localMediaDb.countEntriesBefore(predicate: predicate, id: id, sort: _pagedSort, reverse: _pagedReverse);
    } catch (error, stack) {
      _log.w('paged index lookup failed for id=$id', error, stack);
      return -1;
    }
  }

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

  /// Rows per lookup query: one bounded page at a time, so a lookup that has to
  /// leave the loaded windows costs latency but never memory.
  static const _lookupChunkSize = 2000;

  @override
  Future<AvesEntry?> firstMatching(bool Function(AvesEntry entry) test) async {
    await _awaitSettled();
    if (!pagedActive) return super.firstMatching(test);
    // Loaded tiles first: a highlight almost always targets a row the view
    // already shows, and reading them costs nothing.
    for (final entry in loadedEntries) {
      if (test(entry)) return entry;
    }
    final predicate = _pagedPredicate;
    if (predicate == null) return super.firstMatching(test);
    // Otherwise ask the database, in bounded id-ordered chunks, stopping at the
    // first match. Rows come in id order rather than the view's date order, so
    // when several rows match (a multi-item move) the one returned can differ
    // from the legacy scan's: either is an item of the scope.
    var afterId = 0;
    while (true) {
      final rows = await localMediaDb.loadWalkWindow(predicate: predicate, afterId: afterId, limit: _lookupChunkSize);
      if (rows.isEmpty) return null;
      for (final row in rows) {
        if (test(row)) return _materialize(row);
      }
      if (rows.length < _lookupChunkSize) return null;
      afterId = rows.last.id;
    }
  }

  @override
  Future<int> indexOfEntry(AvesEntry entry) async {
    await _awaitSettled();
    return indexOfId(entry.id);
  }

  /// Waits for the first load's decision while one is still pending, so a lookup
  /// that arrives early (a page's init highlight) is not answered by the empty
  /// pre-resolution list. A fixed-selection, morphed or blocked lens has already
  /// settled, and a disposed one never will.
  Future<void> _awaitSettled() async {
    if (pagedActive || _morphed || _blocked || fixedSelection != null || _ready.isCompleted) return;
    await ready;
  }

  /// Loads [row]'s window so its position becomes real (the highlight tracker
  /// reads `indexOf`), and answers the loaded entry when it materialized.
  Future<AvesEntry> _materialize(AvesEntry row) async {
    final index = await indexOfId(row.id);
    if (index < 0) return row;
    await fillAround(index);
    final entry = sortedEntries[index];
    return entry is SkeletonEntry ? row : entry;
  }

  @override
  void refresh() {
    // A run updates the source batch by batch: reloading the view per batch would
    // re-resolve counts, headers and summaries thousands of times. One reload at
    // the end of the run is enough.
    final run = EntryFeedRun.current;
    if (run != null) {
      run.needsViewRefresh = true;
      return;
    }
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
      // The collection page mounts while the home page is still loading the
      // library. Resolving now would find `loadedScope` unset and start a second
      // full load, which disposes the entries the first pass is still analysing
      // and does the work twice: wait for that pass to finish loading instead.
      await _awaitInFlightLoad();
      if (!_current(gen)) return;

      final prefs = collectionPagingPrefs;
      await prefs.init();
      if (!_current(gen)) return;

      // A first run is known before anything is read: the library is about to be
      // written, so say so from the first frame instead of a bare "loading" that
      // only turns into an explanation a second later. A reload that lands while
      // the import runs must not start a second one: it only re-resolves the
      // rows that have arrived.
      final needsImport = !prefs.importComplete && !await _recoverImportMarker(prefs);
      if (!_current(gen)) return;
      // Another surface may already be importing (a second collection route):
      // join that run instead of scanning MediaStore again.
      final importRunning = pagedImportStatus.active;
      final startImport = needsImport && !_importingRows && !importRunning;
      final joinImport = needsImport && importRunning && !_importingRows;
      if (startImport || joinImport) {
        _importingRows = true;
        _grewDuringImport = false;
        if (startImport) {
          pagedImportStatus.begin();
          source.setProgress(done: 0, total: 0);
        }
        // Surfaces switch to the browse-only browser on this frame rather than
        // after the first batch: waiting would show a loading grid first.
        notifyListeners();
      }

      // The view is about to resolve: say so instead of showing an empty
      // collection with a zero count, which reads as "your library is gone"
      // during the (slow, first-run) bootstrap. A refresh over a view that is
      // already on screen keeps its state: only the first resolve, or a run
      // that is still writing, has nothing to show yet.
      if (_importingRows || !_ready.isCompleted) source.state = SourceState.loading;

      await PagedBootstrap.ensure(source);
      if (!_current(gen)) return;

      // Steady-state MediaStore sync: one cheap generation query when quiet,
      // bounded change handling otherwise. New files appear without a restart.
      await PagedDiscoverer().syncIfChanged();
      if (!_current(gen)) return;

      var decision = await const CollectionEngineRouter().resolve(filters: filters);
      if (!_current(gen)) return;

      if (startImport) {
        // Unseen library, or an import that never finished: fill the database
        // (resumably) and paint after the first batch, then re-resolve against
        // what has landed. The empty-scope case is covered too: an empty
        // library completes with zero rows and stops asking.
        await _initialImport(gen);
        if (!_current(gen)) return;
        decision = await const CollectionEngineRouter().resolve(filters: filters);
        if (!_current(gen)) return;
      } else if (joinImport) {
        // The run belongs to another surface: its status ending is our signal,
        // and its rows are already reaching the shared index.
        _followExternalImport(gen);
      }

      if (decision.route == CollectionRoute.legacy) {
        await _enterLegacy(decision, gen);
        return;
      }
      await _enterPaged(decision, gen);
    } catch (error, stack) {
      if (!_current(gen)) return;
      _log.e('paged reload failed', error, stack);
      if (_pagedActive) {
        // A view that already has a window keeps it: a transient read failure
        // (a busy database while the import writes) must not blank the grid,
        // which would read as the library vanishing and coming back.
      } else {
        _enterBlocked('the reload failed');
      }
    } finally {
      _reloading = false;
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Waits for a load started outside the lens (the home page loading the
  /// library on launch, or the analyzer reloading it) to leave
  /// [SourceState.loading].
  ///
  /// Only the load phase is waited for: `loadedScope` is assigned before the
  /// analysis that follows, and that analysis stays visible through the legacy
  /// progress display. A load that never settles would leave the whole app on its
  /// loading screen anyway, so this adds no wait that was not already there.
  Future<void> _awaitInFlightLoad() {
    // Our own import keeps the source in `loading` without being an external
    // load: waiting for it here would deadlock the reload that paints it.
    if (_importingRows) return Future<void>.value();
    if (source.state != SourceState.loading) return Future<void>.value();
    void listener() {
      if (source.state == SourceState.loading) return;
      _cancelInFlightLoadWait();
    }

    final completer = _inFlightLoadWait = Completer<void>();
    _inFlightLoadListener = listener;
    source.stateNotifier.addListener(listener);
    return completer.future;
  }

  /// Releases the wait, resuming the reload so it can observe the disposal and
  /// bail out. Also called by the listener when the load settles.
  void _cancelInFlightLoadWait() {
    final listener = _inFlightLoadListener;
    if (listener != null) {
      source.stateNotifier.removeListener(listener);
      _inFlightLoadListener = null;
    }
    final completer = _inFlightLoadWait;
    _inFlightLoadWait = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Restores the import flag from the database when preferences lost it.
  ///
  /// The marker is written next to the imported rows, so a preference reset over
  /// a whole database cannot read as "never imported" — which would bring the
  /// browser back over a complete library and scan it a second time. Returns
  /// whether the library is known complete.
  Future<bool> _recoverImportMarker(CollectionPagingPrefs prefs) async {
    try {
      await localMediaDb.init();
      if (!await localMediaDb.readImportComplete()) return false;
      await prefs.setImportComplete(true);
      _log.i('paged import marker recovered from the database');
      return true;
    } catch (error, stack) {
      _log.w('paged import marker read failed', error, stack);
      return false;
    }
  }

  /// Fills an empty database without making the first screen wait for it.
  ///
  /// Only the first batch is awaited: the caller then resolves and paints, and
  /// the rest of the library streams in behind the grid. Because MediaStore
  /// hands entries over newest first, later batches only append older rows at
  /// the tail, so nothing already on screen is reordered.
  Future<void> _initialImport(int gen) async {
    final discoverer = PagedDiscoverer();
    if (!collectionPagingPrefs.importExplained) {
      // One-time: what the app is doing and how long it takes. The settings
      // page keeps the same explanation available afterwards.
      pagedImportStatus.requestExplainer();
    }
    notifyListeners();

    // The platform row count is the denominator; it runs alongside the first
    // batch so it never delays the first paint.
    unawaited(discoverer.countEntries().then((total) {
      if (!_current(gen) || total <= 0) return;
      pagedImportStatus.update(pagedImportStatus.done, total: total);
      source.setProgress(done: pagedImportStatus.done, total: total);
    }));

    final firstBatch = Completer<void>();
    final import = discoverer.importAll(
      firstBatchLimit: CollectionPagingPrefs.firstImportBatchSize,
      onRows: importRowsSink,
      onProgress: (done) {
        pagedImportStatus.update(done);
        if (_current(gen)) source.setProgress(done: done, total: pagedImportStatus.total);
        _growWhileImporting(done, gen);
      },
      onFirstBatch: () async {
        if (!firstBatch.isCompleted) firstBatch.complete();
      },
    );
    unawaited(import.then((imported) async {
      _log.i('paged bulk import complete: $imported rows');
      if (!firstBatch.isCompleted) firstBatch.complete();
      // Record completion next to the rows first: preferences can be reset,
      // the database cannot without losing the library itself.
      try {
        await localMediaDb.writeImportComplete();
      } catch (error, stack) {
        _log.w('paged import marker write failed', error, stack);
      }
      await collectionPagingPrefs.setImportComplete(true);
      _onImportFinished(gen);
    }, onError: (Object error, StackTrace stack) {
      // Never leave the caller waiting on a batch that will not come.
      if (!firstBatch.isCompleted) firstBatch.complete();
      _log.e('paged bulk import failed', error, stack);
      _importingRows = false;
      pagedImportStatus.end();
      // The database now holds part of the library: keep the browser, which
      // reads the media store, and let the user retry instead of handing a
      // truncated collection over as if the import had succeeded.
      libraryPhase.markFailed();
      source.setProgress(done: 0, total: 0);
      if (!_current(gen)) return;
      // Settle without refreshing: a reload would immediately retry the same
      // failing import. The next launch tries again, and rows already written
      // stay browsable in the meantime.
      source.state = SourceState.ready;
      notifyListeners();
    }));

    await firstBatch.future;
  }

  /// Lets the grid grow once, midway through a long import.
  ///
  /// The view is resolved against the rows that exist at that moment. Without
  /// this, a library that takes a minute to stream would show its first batch
  /// until the very end, which reads as a collection that stops at 250 items.
  void _growWhileImporting(int done, int gen) {
    if (!_pagedActive || _grewDuringImport) return;
    final total = pagedImportStatus.total;
    if (total <= 0 || done < total ~/ 2) return;
    _grewDuringImport = true;
    if (_current(gen)) refresh();
  }

  /// Follows an import another surface owns: when its shared status ends, this
  /// lens settles and re-resolves, without starting a second scan.
  void _followExternalImport(int gen) {
    if (_externalImportListener != null) return;
    // The run may have ended between the flag read and this call.
    if (!pagedImportStatus.active) {
      _onImportFinished(gen);
      return;
    }
    void listener() {
      if (pagedImportStatus.active) return;
      pagedImportStatus.removeListener(listener);
      _externalImportListener = null;
      _onImportFinished(gen);
    }

    _externalImportListener = listener;
    pagedImportStatus.addListener(listener);
  }

  /// Settles the state and re-resolves once the import is over, so the view
  /// picks up the whole library (or stops claiming it is still organizing).
  void _onImportFinished(int gen) {
    _importingRows = false;
    pagedImportStatus.end();
    // The import's counter must not outlive it: the loading screen renders any
    // progress it finds, so a stale "32804/32804" would read as a re-import on
    // the next resolve.
    source.setProgress(done: 0, total: 0);
    if (!_current(gen)) return;
    source.state = SourceState.ready;
    notifyListeners();
    if (_reloading) {
      // The initial reload is still resolving the first batch: reload again
      // once it settles instead of dropping this refresh.
      unawaited(_ready.future.then((_) {
        if (_current(gen)) refresh();
      }));
    } else {
      refresh();
    }
  }

  bool _current(int gen) => gen == _reloadGen && !_disposed;

  /// Legacy path inside the paged lens: only taken when a full load is provably
  /// safe (see `CollectionEngineRouter.allowFullLoad`), so a huge library is
  /// never materialized here. A scope the SQL layer cannot express then shows the
  /// unsupported notice instead. A scope it *can* express is paged, even though
  /// it fell below the size threshold: it is the library that is too large, and
  /// one small album is exactly what the windowed path is for. Display calls
  /// delegate to `super` afterwards.
  Future<void> _enterLegacy(EngineDecision decision, int gen) async {
    if (source.loadedScope != CollectionSource.fullScope) {
      // A library that is still being written cannot be materialized: a count
      // taken now is the part that has landed, not the library, and materializing
      // it would walk every row the import is about to add.
      final allowed = !_importingRows && await const CollectionEngineRouter().allowFullLoad();
      if (!_current(gen)) return;
      if (!allowed) {
        final predicate = decision.predicate;
        if (predicate != null) {
          await _enterPaged(EngineDecision.paged(predicate: predicate, total: decision.total), gen);
          return;
        }
        _enterBlocked('the scope needs the in-memory path and a full load is unsafe');
        return;
      }
      await source.init(scope: CollectionSource.fullScope);
      if (!_current(gen)) return;
    }
    super.refresh();
    if (!_current(gen)) return;
    _detachSummariesForLegacy();
    _detachCatalogWorker();
    _blocked = false;
    _morphed = true;
    _pagedActive = false;
    notifyListeners();
  }

  /// Marks the view unusable, saying why in the log.
  ///
  /// The notice the grid shows is generic, so the reason would otherwise be lost:
  /// this is the only way to tell a refused view from a legitimately empty one.
  void _enterBlocked([String? reason]) {
    _log.d('paged view blocked${reason == null ? '' : ': $reason'}');
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
    final resolved = decision.predicate;
    if (resolved == null) {
      _enterBlocked('the view has no window predicate');
      return;
    }
    // A view may add its own atoms (the slideshow's video exclusion): they are
    // not collection filters but they still define the rows the view contains,
    // so they ride on the same predicate the totals and windows use.
    final base = _extraFragments.isEmpty
        ? resolved
        : CollectionWindowPredicate(
            conjunction: [...resolved.conjunction, ..._extraFragments],
            trashedOnly: resolved.trashedOnly,
          );
    final dayRows = _dayRows;
    final mosaic = _mosaic;
    // Stacks ride on the same predicate as the totals and windows: a member shows
    // while its tile is in the same scope, so nothing disappears when a filter
    // splits a group. A library without stacks skips the filter entirely, and the
    // calendar projection keeps every frame of its day.
    final predicate = _stackEntries && !dayRows && await _hasStacks() ? _withStackFilter(base) : base;
    final prefs = collectionPagingPrefs;
    await prefs.init();
    if (!_current(gen)) return;

    final grouping = _resolveGrouping();
    if (grouping == null) {
      _enterBlocked('the view has no paged grouping');
      return;
    }

    // About to resolve: a first resolve has nothing to show yet, so say loading
    // rather than an empty collection with a zero count.
    _settleState(resolving: true);
    final sort = settings.getEffectiveCollectionSortFactor(filters);
    final reverse = settings.getEffectiveCollectionSortReverse(filters);
    final windowSize = prefs.windowSize;
    final prefetch = prefs.prefetchScreens;
    final total = dayRows
        ? await localMediaDb.countDays(predicate: predicate)
        : await localMediaDb.countEntries(predicate);
    if (!_current(gen)) return;
    // Denominator for the count line. A calendar view counts days and a filtered
    // view counts matches, so neither can be compared with the library size: the
    // pair is only shown when the view *is* the library.
    _libraryTotal = dayRows || filters.isNotEmpty ? 0 : total;

    final headers = dayRows
        ? await localMediaDb.loadDaySectionHeaders(predicate: predicate, reverse: reverse)
        : await localMediaDb.loadSectionHeaders(
            predicate: predicate,
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
        fetch: (windowIndex, limit, offset) => dayRows
            ? localMediaDb.loadDayWindow(
                predicate: predicate,
                dateFromMillis: range.dateFromMillis,
                dateToMillis: range.dateToMillis,
                reverse: reverse,
                limit: limit,
                offset: offset,
              )
            : localMediaDb.loadEntryWindow(
                predicate: predicate,
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
          // Deep metadata first, then the layout's own derivations: a windowed
          // row must end up with what an in-memory row has, or the info sheet,
          // tile badges and place surfaces read as empty.
          unawaited(_attachWindowExtras(predicate, state, rows, dayRows: dayRows, gen: gen));
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

    _mosaicRatios.clear();
    if (mosaic) {
      // The mosaic packs a whole section, so its ratios are measured per section
      // and the layout waits for them (a section renders as its header until
      // then) instead of packing skeletons that would reflow on the next fill.
      for (final state in states) {
        unawaited(_loadSectionRatios(predicate, state, sort, reverse, gen));
      }
    }

    _total = total;
    _sectionStates = List.unmodifiable(states);
    _flat = PagedFlatList(List.unmodifiable(lists.values.toList()));
    sections = Map.unmodifiable(lists);
    _pagedPredicate = predicate;
    _pagedEntryPredicate = base;
    // The calendar projection counts days, so its entry total needs its own read.
    _entryTotal = dayRows || !identical(base, predicate) ? await localMediaDb.countEntries(base) : total;
    _pagedSort = sort;
    _pagedReverse = reverse;
    _pagedDayRows = dayRows;
    _blocked = false;
    _morphed = false;
    _pagedActive = true;
    if (grouping == SectionGrouping.album) {
      PagedBootstrap.feedDirectories(source, headers);
    }
    _attachSummaries();
    // The window is ready now: settle the state and publish it *before* the
    // filter summaries, whose aggregates are the slow part. While the state was
    // still `loading`, the app bar read "loading" with no count for as long as
    // that query took — minutes on a fresh 32k library — even though the grid
    // and the total were already there.
    _settleState();
    notifyListeners();
    if (!_current(gen)) return;
    // Eager albums on first entry; refreshes already-loaded domains (tags,
    // locations) whose rows may have changed. Never throws: a failed domain
    // stays unloaded and retries on next touch.
    await _summaries!.reload();
    if (!_current(gen)) return;
    // Backlog catalog runs behind the instant grid: the worker fills tags,
    // precise dates and countries in bounded chunks without blocking display.
    // It waits for a running import: cataloguing a half-imported database would
    // sweep the same rows twice and report a total that keeps growing.
    _attachCatalogWorker();
    if (!_importingRows) unawaited(_runCatalogBacklog());
    notifyListeners();
  }

  /// Settles the source state: `loading` still means "the library is being
  /// organized", and only this lens knows when that is over.
  ///
  /// Cataloguing owns its own states (`cataloguing`, `locating*`): the worker
  /// sets them and writes `ready` back when its drain ends. Overwriting them
  /// here made the app bar flip between the count line and the catalog clock on
  /// every refresh.
  ///
  /// [resolving] is the "about to resolve, nothing to show yet" case: a first
  /// resolve must say loading instead of showing an empty collection. The final
  /// settle never passes it — `_ready` completes only after this returns, so
  /// keying the settle off it left every new lens stuck in `loading`.
  void _settleState({bool resolving = false}) {
    if (_importingRows || (resolving && !_ready.isCompleted)) {
      source.state = SourceState.loading;
      return;
    }
    switch (source.state) {
      case SourceState.cataloguing:
      case SourceState.locatingCountries:
      case SourceState.locatingPlaces:
        return;
      case SourceState.loading:
      case SourceState.ready:
        source.state = SourceState.ready;
    }
  }

  void _attachSummaries() {
    // Shared per source: the provider has to outlive this lens, because the
    // album/tag/place pages are top-level routes that dispose the collection.
    attachPagedSummaries(source);
    _summaries = pagedSummariesFor(source);
  }

  /// Detaches the provider for a legacy view. The shared instance is only
  /// invalidated, not forgotten: the next paged view reuses it.
  void _detachSummariesForLegacy() {
    detachPagedSummaries(source);
    _summaries = null;
  }

  void _attachCatalogWorker() {
    _catalogWorker ??= _catalogWorkerFactory(source: source);
  }

  Future<void> _runCatalogBacklog() async {
    final worker = _catalogWorker;
    if (worker == null || worker.isRunning) return;
    final uncatalogued = await _probeUncatalogued();
    if (uncatalogued == 0) return;
    if (catalogPrompt.shouldAsk(askBeforeCatalog: collectionPagingPrefs.askBeforeCatalog, uncatalogued: uncatalogued)) {
      // A backlog this large is long invisible work, so it waits for an answer
      // instead of starting silently. The lens only raises the question: the UI
      // layer owns dialogs, and answers it by calling [runCatalogBacklog].
      catalogPrompt.markAsked(uncatalogued);
      return;
    }
    await _sweepBacklog(worker, uncatalogued);
  }

  /// Sweeps the catalog backlog now, starting with this view's own scope.
  ///
  /// Public because the prompt's answer is what starts a held-back sweep.
  Future<void> runCatalogBacklog() async {
    final worker = _catalogWorker;
    if (worker == null || worker.isRunning) return;
    final uncatalogued = await _probeUncatalogued();
    if (uncatalogued == 0) return;
    await _sweepBacklog(worker, uncatalogued);
  }

  /// Catalogues one album's rows, on demand from its section header badge.
  ///
  /// Unlike [runCatalogBacklog] this is a one-shot, album-scoped pass: the badge
  /// names a single album, so the worker stops at its rows instead of carrying
  /// on into the rest of the library.
  Future<void> catalogAlbum(String directory) async {
    final worker = _catalogWorker;
    if (worker == null || worker.isRunning) return;
    final predicate = predicateForFilters({StoredAlbumFilter(directory, null)});
    if (predicate == null) return;
    _settleAfterSweep(await worker.run(scope: predicate, scopedOnly: true));
  }

  /// Rows of [directory] that still need cataloguing, for its header badge.
  int albumUncatalogued(String directory) => _summaries?.albumUncatalogued(directory) ?? 0;

  Future<int> _probeUncatalogued() async {
    try {
      return await localMediaDb.countUncatalogued();
    } catch (error, stack) {
      _log.w('paged catalog backlog probe failed', error, stack);
      return 0;
    }
  }

  /// How many rows of the current view still need cataloguing.
  Future<int> _probeScopedUncatalogued() async {
    final predicate = _pagedPredicate;
    if (predicate == null) return 0;
    try {
      return await localMediaDb.countUncatalogued(predicate);
    } catch (error, stack) {
      _log.w('paged scoped catalog backlog probe failed', error, stack);
      return 0;
    }
  }

  /// Sweeps the backlog: the view's own scope first, then the rest of the
  /// library — unless the analysis service owns that rest, in which case the app
  /// worker serves only the view so the two never race on the same rows.
  ///
  /// A view large enough to be worth it preempts the service: the sweep is
  /// cancelled, the view is served with the device to itself, and the service is
  /// re-enqueued to resume the backlog. A small view is served alongside the
  /// running sweep instead, since stopping it would waste more work than the
  /// view is worth.
  Future<void> _sweepBacklog(PagedCatalogWorker worker, int uncatalogued) async {
    final delegated = shouldDelegateCatalogToService(canUseAnalysisService: settings.canUseAnalysisService, uncatalogued: uncatalogued);
    if (!delegated) {
      _settleAfterSweep(await worker.run(scope: _pagedPredicate));
      return;
    }
    if (shouldPreemptCatalogService(serviceDelegated: delegated, scopedUncatalogued: await _probeScopedUncatalogued())) {
      await cancelPagedAnalysisService();
      final catalogued = await worker.run(scope: _pagedPredicate, scopedOnly: true);
      await startPagedAnalysisService();
      _settleAfterSweep(catalogued);
      return;
    }
    await startPagedAnalysisService();
    _settleAfterSweep(await worker.run(scope: _pagedPredicate, scopedOnly: true));
  }

  void _detachCatalogWorker() {
    _catalogWorker?.stop();
    _catalogWorker = null;
  }

  /// Lazily backfills fine addresses once the locations domain loads. Cheap
  /// probe first: without unlocated GPS rows this is a no-op, so repeated
  /// locations reloads stay harmless. A request that lands while the eager
  /// pass still runs is queued by the worker instead of dropped.
  Future<void> _runPlacesBacklog() async {
    final worker = _catalogWorker;
    if (worker == null) return;
    try {
      if ((await localMediaDb.loadUnlocatedGpsIds(after: LocalMediaDb.backlogStart, limit: 1)).isEmpty) return;
    } catch (error, stack) {
      _log.w('paged places backlog probe failed', error, stack);
      return;
    }
    await worker.runPlaces();
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

  /// Probes whether the library hides anything behind a stack tile.
  Future<bool> _hasStacks() async {
    try {
      return await localMediaDb.hasStackedEntries();
    } catch (error, stack) {
      _log.w('paged stack probe failed', error, stack);
      return false;
    }
  }

  /// Rebuilds the burst index after the patterns changed, then refreshes so the
  /// view picks up the re-settled tiles.
  Future<void> _rebuildStackIndex() async {
    try {
      await localMediaDb.rebuildStackKeys();
    } catch (error, stack) {
      _log.w('paged stack rebuild failed', error, stack);
      return;
    }
    if (_disposed || _morphed) return;
    refresh();
  }

  /// Appends the stack filter to [predicate]: a member hides only *while* its
  /// tile is in the same scope, so it comes back when a filter or the bin takes
  /// the tile away instead of disappearing.
  ///
  /// The inner query is uncorrelated and aliases the entry table `e` again so the
  /// compiled fragments apply verbatim; SQLite materializes it as a set, which
  /// keeps the total a scan rather than a probe per row.
  CollectionWindowPredicate _withStackFilter(CollectionWindowPredicate predicate) {
    final joins = [
      if (predicate.requires.contains(WindowTable.dateTaken)) 'LEFT JOIN dateTaken dt ON dt.id = e.id',
      if (predicate.requires.contains(WindowTable.metadata)) 'LEFT JOIN metadata m ON m.id = e.id',
      if (predicate.requires.contains(WindowTable.address)) 'LEFT JOIN address a ON a.id = e.id',
    ].join(' ');
    final conditions = <String>[
      predicate.trashedOnly ? 'e.trashed != 0' : 'e.trashed = 0',
      for (final fragment in predicate.conjunction) fragment.sql,
    ];
    return CollectionWindowPredicate(
      conjunction: [
        ...predicate.conjunction,
        (
          // `NOT IN` (the ids are primary keys, so no NULL can poison it): a
          // member shows exactly when its tile is not in this scope.
          sql: '(e.stackTileId IS NULL OR e.stackTileId NOT IN (SELECT e.id FROM entry e ${joins.isEmpty ? '' : '$joins '}WHERE ${conditions.join(' AND ')}))',
          variables: [for (final fragment in predicate.conjunction) ...fragment.variables],
          requires: predicate.requires,
        ),
      ],
      trashedOnly: predicate.trashedOnly,
    );
  }

  /// Attaches the deep metadata of a freshly filled window, then whatever the
  /// layout derives from it (day stacks / stack members).
  ///
  /// The window SELECT reads the entry row plus its catalogued date and trash
  /// details only, so tags, ratings, titles, coordinates and the catalogued mime
  /// would otherwise read as absent: the info sheet would drop its location
  /// section, tiles would lose their rating/type badges, and an entry's mime
  /// would fall back to the source one. Two indexed lookups per window (bounded
  /// by the window size) close that gap, making a windowed row equivalent to an
  /// in-memory one.
  ///
  /// Metadata is attached *before* the day/stack passes because those replace the
  /// row with `copyWith(stackedEntries:)`, which carries the metadata over — the
  /// order is what keeps it from being dropped.
  Future<void> _attachWindowExtras(CollectionWindowPredicate predicate, _SectionState state, List<AvesEntry> rows, {required bool dayRows, required int gen}) async {
    final ids = {for (final entry in rows) entry.id};
    if (ids.isNotEmpty) {
      var changed = false;
      try {
        final metaById = {for (final m in await localMediaDb.loadCatalogMetadataById(ids)) m.id: m};
        final addressById = {for (final a in await localMediaDb.loadAddressesById(ids)) a.id: a};
        if (!_current(gen)) return;
        for (final entry in rows) {
          final meta = metaById[entry.id];
          if (meta != null) {
            entry.catalogMetadata = meta;
            changed = true;
          }
          final address = addressById[entry.id];
          if (address != null) {
            entry.addressDetails = address;
            changed = true;
          }
        }
      } catch (error, stack) {
        // A metadata failure must not cost the window its tiles: the day/stack
        // passes below still run.
        _log.w('paged window metadata load failed', error, stack);
      }
      if (changed) notifyListeners();
    }
    if (dayRows) {
      await _attachDayMembers(predicate, state, rows, gen);
    } else if (_stackEntries) {
      await _attachStackMembers(state, rows, gen);
    }
  }

  /// Coalesces the in-place metadata patches triggered by catalog/locate passes.
  ///
  /// The sweep persists every 50 rows, so patching per event would still rebuild
  /// the grid hundreds of times; one patch per [_metadataPatchInterval] keeps
  /// tile badges and dates filling in visibly without any structural change.
  static const _metadataPatchInterval = Duration(milliseconds: 200);

  void _scheduleMetadataPatch() {
    if (!pagedActive) {
      // Morphed/blocked views materialize their rows: the legacy refresh is the
      // right (and cheap) answer there, and there are no windows to patch.
      refresh();
      return;
    }
    if (_metadataPatchTimer != null) return;
    _metadataPatchTimer = Timer(_metadataPatchInterval, () {
      _metadataPatchTimer = null;
      unawaited(_patchMountedMetadata());
    });
  }

  /// Rewrites the metadata of the tiles already materialized, in place.
  ///
  /// Cataloguing changes row content only: the section list, its headers and
  /// the totals stay valid, so a re-resolve would rebuild them into skeletons
  /// for nothing. Section drift caused by corrected dates is settled once by the
  /// refresh at the end of a sweep.
  Future<void> _patchMountedMetadata() async {
    if (_patchingMetadata || _disposed || !pagedActive) return;
    _patchingMetadata = true;
    try {
      final byId = <int, List<AvesEntry>>{};
      for (final state in _sectionStates) {
        for (final entry in state.list.loaded.values) {
          (byId[entry.id] ??= []).add(entry);
        }
      }
      if (byId.isEmpty) return;
      var changed = false;
      for (final slice in byId.keys.slices(500)) {
        final ids = slice.toSet();
        final metaById = {for (final m in await localMediaDb.loadCatalogMetadataById(ids)) m.id: m};
        final addressById = {for (final a in await localMediaDb.loadAddressesById(ids)) a.id: a};
        if (_disposed) return;
        for (final id in slice) {
          final meta = metaById[id];
          final address = addressById[id];
          if (meta == null && address == null) continue;
          for (final entry in byId[id]!) {
            if (meta != null) entry.catalogMetadata = meta;
            if (address != null) entry.addressDetails = address;
            changed = true;
          }
        }
      }
      if (changed) notifyListeners();
    } catch (error, stack) {
      // A failed patch must not cost the grid its tiles: the next pass or the
      // end-of-sweep refresh still lands the metadata.
      _log.w('paged metadata patch failed', error, stack);
    } finally {
      _patchingMetadata = false;
    }
  }

  /// One settle after a sweep that catalogued something.
  ///
  /// Catalog dates can move a row between sections, which no in-place patch can
  /// express. This is the only rebuild a catalog pass causes, and it is skipped
  /// when the sweep made no progress (a row that keeps failing must not start an
  /// endless refresh/retry chain).
  void _settleAfterSweep(int cataloguedRows) {
    if (cataloguedRows <= 0 || _disposed || !pagedActive || _importingRows) return;
    refresh();
  }

  /// Attaches the members of the stacks the window's tiles show, so a tile can
  /// render its stack badge and the viewer can page through its frames.
  ///
  /// Fired after the window is on screen rather than blocking it: one frame
  /// without its badge costs less than making every window wait for a query.
  Future<void> _attachStackMembers(_SectionState state, List<AvesEntry> rows, int gen) async {
    final ids = {for (final entry in rows) entry.id};
    if (ids.isEmpty) return;
    final Map<int, List<AvesEntry>> stacks;
    try {
      stacks = await localMediaDb.loadStackMembers(ids);
    } catch (error, stack) {
      _log.w('paged stack member load failed', error, stack);
      return;
    }
    if (stacks.isEmpty || !_current(gen)) return;
    var changed = false;
    stacks.forEach((tileId, members) {
      final local = state.list.idToLocal[tileId];
      if (local == null) return;
      final tile = state.list.loaded[local];
      if (tile == null) return;
      state.list.loaded[local] = tile.copyWith(stackedEntries: members);
      changed = true;
    });
    if (!changed) return;
    _reindexFlat();
    notifyListeners();
  }

  /// Attaches each calendar row's day entries, so a tile shows its day stack and
  /// the viewer can page through the day.
  ///
  /// A day stack exists only in this layout — it is not the persisted stack
  /// index, and must not hide a row from any other view — so it is read per
  /// window, like the burst frames are.
  Future<void> _attachDayMembers(CollectionWindowPredicate predicate, _SectionState state, List<AvesEntry> rows, int gen) async {
    final days = <DateTime>{};
    for (final entry in rows) {
      final date = entry.bestDate;
      if (date != null) days.add(calendar.ops.dateOnly(date));
    }
    if (days.isEmpty) return;

    final Map<DateTime, List<AvesEntry>> membersByDay;
    try {
      membersByDay = await localMediaDb.loadDayMembers(predicate: predicate, days: days, reverse: _pagedReverse);
    } catch (error, stack) {
      _log.w('paged day member load failed', error, stack);
      return;
    }
    if (membersByDay.isEmpty || !_current(gen)) return;

    var changed = false;
    for (final entry in rows) {
      final date = entry.bestDate;
      if (date == null) continue;
      final members = membersByDay[calendar.ops.dateOnly(date)];
      // A lone entry is not a stack, exactly like the legacy date grouping.
      if (members == null || members.length < 2) continue;
      final local = state.list.idToLocal[entry.id];
      if (local == null) continue;
      state.list.loaded[local] = entry.copyWith(stackedEntries: members);
      changed = true;
    }
    if (!changed) return;
    _reindexFlat();
    notifyListeners();
  }

  /// Measures one section for the mosaic packing, without reading its entries
  /// (which may still be skeletons).
  Future<void> _loadSectionRatios(CollectionWindowPredicate predicate, _SectionState state, SortFactor sort, bool reverse, int gen) async {
    final range = _rangeFor(state.header);
    final List<double> ratios;
    try {
      ratios = await localMediaDb.loadRatioChannel(
        predicate: predicate,
        directoryEquals: range.directoryEquals,
        directoryEqualsNull: range.directoryEqualsNull,
        dateFromMillis: range.dateFromMillis,
        dateToMillis: range.dateToMillis,
        ratingEquals: range.ratingEquals,
        sort: sort,
        reverse: reverse,
      );
    } catch (error, stack) {
      _log.w('paged ratio channel load failed', error, stack);
      return;
    }
    if (!_current(gen)) return;
    _mosaicRatios[state.key] = ratios;
    notifyListeners();
  }

  /// Maps the effective sort/section factors to a SQL grouping, or null when
  /// the combination needs the legacy path.
  SectionGrouping? _resolveGrouping() {
    if (fixedSort) return SectionGrouping.single;
    // The calendar layout shows one row per day under month sections.
    if (tileLayout == TileLayout.calendar) return SectionGrouping.month;
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
    // A caller that names other filters (or a fixed selection) asks for a lens
    // over *that* scope, so it is resolved like any other collection: serving it
    // from this lens's windows would silently show the wrong entries. The view's
    // own atoms ride along, exactly as `resolve` would apply them here.
    if (filters != null || fixedSelection != null) {
      return PagedCollectionLens(
        source: source ?? this.source,
        filters: filters ?? this.filters,
        id: id,
        fixedSort: fixedSort,
        fixedSelection: fixedSelection,
        stackEntries: _stackEntries,
        extraFragments: _extraFragments,
      );
    }
    // Viewer copies share the live windows instead of snapshotting loaded rows,
    // so swiping past the loaded neighbourhood keeps resolving.
    if (_pagedActive && !_blocked) {
      return PagedViewerCopy(parent: this);
    }
    // Not a windowed view right now: hand the loaded rows over.
    return PagedCollectionLens(
      source: source ?? this.source,
      filters: this.filters,
      id: id,
      fixedSort: fixedSort,
      fixedSelection: loadedEntries,
      stackEntries: _stackEntries,
      extraFragments: _extraFragments,
    );
  }
}
