import 'dart:async';

import 'package:aves/features/collection_paging/catalog/catalog_progress.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/geo/countries.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/catalog.dart';
import 'package:aves/model/entry/extensions/location.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/location/location.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog('log.collection_paging');

/// Background catalog + offline-country worker for paged collections.
///
/// The grid paints instantly from the MediaStore mirror (no per-file I/O),
/// while this worker fills in the deep metadata underneath in bounded chunks:
/// tags, precise dates and ratings via [catalogEntry], countries via
/// [locateCountry], fine places via [locatePlaces] ([runPlaces] only).
/// Resumable: finished rows are skipped by the keyset range queries, so an
/// interrupted run continues instead of restarting.
///
/// Cadence mirrors the legacy `analyze` path (`TagMixin`/`LocationMixin`
/// thresholds), and completion flows through the same source events, so the
/// lens refresh and summary reload need no new wiring.
class PagedCatalogWorker {
  final CollectionSource source;
  final LocalMediaDb database;
  final Future<void> Function(AvesEntry entry) catalogEntry;
  final Future<AddressDetails?> Function(AvesEntry entry) locateCountry;
  final Future<AddressDetails?> Function(AvesEntry entry) locatePlaces;
  final Future<bool> Function() canLocate;

  bool _draining = false;
  bool _stopRequested = false;
  bool _pendingRun = false;
  bool _pendingPlaces = false;
  bool _pendingScopedOnly = false;
  CollectionWindowPredicate? _pendingScope;

  /// Whether the view that owns this worker is the one on screen.
  ///
  /// A parked scope must not drive the library-wide state: its drain can still
  /// reach its `finally` after the user has moved to another page, and settling
  /// the state there would flip that page's app bar to ready mid-resolve.
  bool Function() isActive = _alwaysActive;

  static bool _alwaysActive() => true;

  void _setState(SourceState value) {
    if (isActive()) source.state = value;
  }

  void _setProgress({required int done, required int total}) {
    if (isActive()) source.setProgress(done: done, total: total);
  }

  new({
    required this.source,
    LocalMediaDb? database,
    Future<void> Function(AvesEntry entry)? catalogEntry,
    Future<AddressDetails?> Function(AvesEntry entry)? locateCountry,
    Future<AddressDetails?> Function(AvesEntry entry)? locatePlaces,
    Future<bool> Function()? canLocate,
  })  : database = database ?? localMediaDb,
        catalogEntry = catalogEntry ?? _defaultCatalogEntry,
        locateCountry = locateCountry ?? _defaultLocateCountry,
        locatePlaces = locatePlaces ?? _defaultLocatePlaces,
        canLocate = canLocate ?? _defaultCanLocate;

  static Future<void> _defaultCatalogEntry(AvesEntry entry) => entry.catalog(background: true, force: false, persist: true);

  static Future<AddressDetails?> _defaultLocateCountry(AvesEntry entry) async {
    if (!entry.hasGps || entry.hasAddress) return null;
    entry.setCountry(await countryTopology.countryCode(entry.latLng!));
    return entry.addressDetails;
  }

  static Future<AddressDetails?> _defaultLocatePlaces(AvesEntry entry) async {
    if (!entry.hasGps || entry.hasFineAddress) return null;
    await entry.locatePlace(background: true, force: false, geocoderLocale: settings.avesLocale);
    return entry.hasFineAddress ? entry.addressDetails : null;
  }

  static Future<bool> _defaultCanLocate() => availability.canLocatePlaces;

  /// Rows between progress reports inside a chunk.
  ///
  /// Reporting per chunk reads as frozen at 0 while the first chunk runs, which
  /// on a cold library is the longest wait of the whole pass.
  static const int progressTickRows = 10;

  /// Catalog metadata rows persisted per database transaction.
  ///
  /// One transaction per entry was the pass's dominant cost (~7 ms each), so a
  /// whole chunk's worth now lands together.
  static const int persistBatchRows = 50;

  bool get isRunning => _draining;

  /// Completes when the current drain, if any, has finished.
  ///
  /// Lets a test wait for the eager passes without polling the database, which
  /// would race the worker's own cooperative yields.
  Future<void> whenIdle() => _draining ? (_drainDone?.future ?? Future<void>.value()) : Future<void>.value();

  Completer<void>? _drainDone;

  /// Rows the session started with, and how many of them are done.
  ///
  /// One session spans every pass of a drain: the counter is what the app bar
  /// shows, and it must not restart when the worker moves from the current
  /// view's rows to the rest of the library. See [CatalogProgressNotifier].
  int _sessionTotal = 0;
  int _sessionDone = 0;
  bool _sessionStarted = false;
  CollectionWindowPredicate? _sessionScope;

  /// Requests the eager backlog (catalog, then offline countries). [scope], when
  /// given, runs *first* in each pass: the rows of the view the user is looking
  /// at are worth cataloguing before the rest of the library, and the unscoped
  /// pass then resumes the backlog they are not part of.
  ///
  /// Serialized with [runPlaces]: a request that arrives mid-pass is queued,
  /// never dropped, and the eager pair always completes before any places pass
  /// so a coarse country write can never clobber a fine address. [stop] halts
  /// cooperatively between chunks.
  ///
  /// [scopedOnly] sweeps [scope] and stops there, for when another owner (the
  /// analysis service) is already taking the rest of the library.
  ///
  /// Returns how many rows this call catalogued. Zero means it joined a drain
  /// already in progress or found nothing to do, which is what tells the caller
  /// whether a settle refresh is worth anything.
  Future<int> run({int chunkSize = 200, CollectionWindowPredicate? scope, bool scopedOnly = false}) {
    _pendingScope = scope;
    _pendingScopedOnly = scopedOnly;
    _pendingRun = true;
    return _drain(chunkSize);
  }

  /// Requests the fine-places backlog. Unlike [run] this never starts on
  /// collection enter: the lens triggers it lazily once the locations domain
  /// loads (i.e. the user opened a places surface). No-op when locating is
  /// unavailable (no geocoder/connectivity).
  Future<void> runPlaces({int chunkSize = 200}) {
    _pendingPlaces = true;
    return _drain(chunkSize);
  }

  /// Single serialized drain loop for every pass, so passes never interleave.
  ///
  /// Returns the rows it catalogued, or 0 when it only joined a drain that was
  /// already running.
  Future<int> _drain(int chunkSize) async {
    if (_draining) return 0;
    _draining = true;
    _drainDone = Completer<void>();
    var catalogued = 0;
    try {
      while (!_stopRequested && (_pendingRun || _pendingPlaces)) {
        if (_pendingRun) {
          _pendingRun = false;
          final scope = _pendingScope;
          final scopedOnly = _pendingScopedOnly;
          _pendingScope = null;
          _pendingScopedOnly = false;
          // An album's badge sweeps one album and stops, so its denominator is
          // that album's backlog; a library sweep counts the whole backlog.
          await _beginSession(scopedOnly ? scope : null);
          await _runCatalog(chunkSize, scope, scopedOnly: scopedOnly);
          if (!_stopRequested) await _runCountries(chunkSize, scope, scopedOnly: scopedOnly);
        }
        if (!_stopRequested && _pendingPlaces) {
          _pendingPlaces = false;
          if (await canLocate()) await _runPlaces(chunkSize);
        }
      }
    } finally {
      catalogued = _sessionDone;
      _draining = false;
      _setState(SourceState.ready);
      // The counters are only meaningful while a pass runs: leaving them behind
      // makes the next "loading" screen show a stale figure that looks like the
      // library is being imported again.
      _setProgress(done: 0, total: 0);
      if (isActive()) catalogProgressNotifier.finish();
      _sessionTotal = 0;
      _sessionDone = 0;
      _sessionStarted = false;
      _sessionScope = null;
      final done = _drainDone;
      _drainDone = null;
      if (done != null && !done.isCompleted) done.complete();
    }
    return catalogued;
  }

  void stop() => _stopRequested = true;

  /// Fixes this drain's denominator before it moves a row.
  ///
  /// The backlog is read once: a denominator that follows the remaining rows
  /// shrinks under the user's eyes, and one read per pass would still jump
  /// between passes. The first run of a drain owns the session; a run queued
  /// behind it continues the same one.
  Future<void> _beginSession(CollectionWindowPredicate? scope) async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    _sessionScope = scope;
    var total = 0;
    try {
      total = await database.countUncatalogued(scope ?? const CollectionWindowPredicate());
    } catch (error, stack) {
      _log.w('catalog backlog count failed', error, stack);
    }
    _sessionTotal = total;
    _sessionDone = 0;
    catalogProgressNotifier.begin(total: total, now: DateTime.now());
    if (total > 0) _reportSession();
  }

  /// Reports the session's progress, clamped so the app bar never reads "N of N"
  /// with rows still to do or "N+1 of N".
  void _reportSession() {
    final total = _sessionTotal;
    final done = total > 0 && _sessionDone > total ? total : _sessionDone;
    _setProgress(done: done, total: total);
    catalogProgressNotifier.update(done: done, total: total, now: DateTime.now());
  }

  /// Absorbs work that other owners did, so the counter does not stall while the
  /// analysis service catalogues alongside the app.
  Future<void> _resyncSession() async {
    if (_sessionTotal <= 0) return;
    try {
      final remaining = await database.countUncatalogued(_sessionScope ?? const CollectionWindowPredicate());
      final done = (_sessionTotal - remaining).clamp(0, _sessionTotal);
      if (done > _sessionDone) {
        _sessionDone = done;
        _reportSession();
      }
    } catch (error, stack) {
      _log.w('catalog backlog resync failed', error, stack);
    }
  }

  /// Runs the catalog pass, scoped rows first when [scope] is given.
  Future<void> _runCatalog(int chunkSize, CollectionWindowPredicate? scope, {required bool scopedOnly}) async {
    if (scope != null) {
      await _runCatalogPass(chunkSize, scope);
      if (_stopRequested || scopedOnly) return;
    }
    await _runCatalogPass(chunkSize, null);
  }

  Future<void> _runCatalogPass(int chunkSize, CollectionWindowPredicate? scope) async {
    final predicate = scope ?? const CollectionWindowPredicate();
    final total = await database.countUncatalogued(predicate);
    if (total == 0) return;
    // A scoped pass sweeps its own scope once from the start. The unscoped pass
    // resumes the persisted sweep and wraps once, so repeated short runs cover
    // the whole backlog instead of re-walking its head.
    var after = scope != null ? LocalMediaDb.backlogStart : await _resumeCursor();
    var wrapped = scope != null;
    final pending = <CatalogMetadata>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveCatalogMetadata(Set.unmodifiable(pending));
      source.onCatalogMetadataChanged();
      pending.clear();
    }

    _setState(SourceState.cataloguing);
    _reportSession();
    while (!_stopRequested) {
      final page = await database.loadUncataloguedEntryIds(predicate: predicate, after: after, limit: chunkSize);
      if (page.isEmpty) {
        if (wrapped) break;
        // The end of the backlog: flush first, so the wrapped walk sees this
        // run's rows as done instead of cataloguing them twice, then wrap once
        // so the rows before the cursor are covered too.
        await flush();
        wrapped = true;
        after = LocalMediaDb.backlogStart;
        await database.saveCatalogCursor(after);
        continue;
      }
      after = page.last;
      if (scope == null) await database.saveCatalogCursor(after);
      var stopCheckCount = 0;
      for (final entry in await _materialize({for (final cursor in page) cursor.id})) {
        try {
          await catalogEntry(entry);
          if (entry.isCatalogued) {
            pending.add(entry.catalogMetadata!);
            // Count real cataloguing only: a row that failed keeps its place in
            // the backlog, and a resumed run must not read as progress.
            _sessionDone++;
            if (_sessionDone % progressTickRows == 0) _reportSession();
          }
        } catch (error, stack) {
          _log.w('paged catalog failed for entry id=${entry.id}', error, stack);
        } finally {
          entry.dispose();
        }
        if (pending.length >= persistBatchRows) await flush();
        if (++stopCheckCount >= 100) {
          stopCheckCount = 0;
          if (_stopRequested) break;
        }
      }
      _reportSession();
      // Cooperative yield between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
    await _resyncSession();
  }

  /// Runs the offline-country pass, scoped rows first when [scope] is given.
  Future<void> _runCountries(int chunkSize, CollectionWindowPredicate? scope, {required bool scopedOnly}) async {
    if (scope != null) {
      await _runCountriesPass(chunkSize, scope);
      if (_stopRequested || scopedOnly) return;
    }
    await _runCountriesPass(chunkSize, null);
  }

  Future<void> _runCountriesPass(int chunkSize, CollectionWindowPredicate? scope) async {
    final predicate = scope ?? const CollectionWindowPredicate();
    var after = LocalMediaDb.backlogStart;
    final pending = <AddressDetails>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveAddresses(Set.unmodifiable(pending));
      source.onAddressMetadataChanged();
      pending.clear();
    }

    _setState(SourceState.locatingCountries);
    // Countries are their own pass but not their own session: the catalog
    // counter keeps its value and clock instead of restarting at zero.
    while (!_stopRequested) {
      final page = await database.loadUnaddressedGpsIds(predicate: predicate, after: after, limit: chunkSize);
      if (page.isEmpty) break;
      after = page.last;
      for (final entry in await _materialize({for (final cursor in page) cursor.id})) {
        try {
          final address = await locateCountry(entry);
          if (address != null) pending.add(address);
        } catch (error, stack) {
          _log.w('paged locate failed for entry id=${entry.id}', error, stack);
        } finally {
          entry.dispose();
        }
        if (pending.length >= LocationMixin.commitCountThreshold) await flush();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }

  /// The persisted sweep position, or the beginning when there is none (or the
  /// stored value cannot be read).
  Future<BacklogCursor> _resumeCursor() async {
    try {
      return await database.loadCatalogCursor() ?? LocalMediaDb.backlogStart;
    } catch (error, stack) {
      _log.w('catalog cursor read failed', error, stack);
      return LocalMediaDb.backlogStart;
    }
  }

  /// Materializes one chunk with catalog metadata and addresses attached
  /// (drives `hasGps`/`latLng`/`hasFineAddress` for the locate passes).
  /// Owned by the worker: callers dispose every entry after use.
  Future<Set<AvesEntry>> _materialize(Set<int> ids) async {
    final entries = await database.loadEntriesById(ids);
    if (entries.isEmpty) return entries;
    final metaById = {for (final m in await database.loadCatalogMetadataById(ids)) m.id: m};
    final addressById = {for (final a in await database.loadAddressesById(ids)) a.id: a};
    for (final entry in entries) {
      entry.catalogMetadata = metaById[entry.id];
      entry.addressDetails = addressById[entry.id];
    }
    return entries;
  }

  Future<void> _runPlaces(int chunkSize) async {
    var after = LocalMediaDb.backlogStart;
    final pending = <AddressDetails>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveAddresses(Set.unmodifiable(pending));
      source.onAddressMetadataChanged();
      pending.clear();
    }

    _setState(SourceState.locatingPlaces);
    // Same rule as the country pass: a locate pass does not restart the
    // catalog session's counter.
    while (!_stopRequested) {
      final page = await database.loadUnlocatedGpsIds(after: after, limit: chunkSize);
      if (page.isEmpty) break;
      after = page.last;
      for (final entry in await _materialize({for (final cursor in page) cursor.id})) {
        try {
          final address = await locatePlaces(entry);
          if (address != null) pending.add(address);
        } catch (error, stack) {
          _log.w('paged locate places failed for entry id=${entry.id}', error, stack);
        } finally {
          entry.dispose();
        }
        if (pending.length >= LocationMixin.commitCountThreshold) await flush();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }
}
