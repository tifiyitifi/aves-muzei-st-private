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
import 'package:aves/model/source/tag.dart';
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
  CollectionWindowPredicate? _pendingScope;

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

  bool get isRunning => _draining;

  /// Requests the eager backlog (catalog, then offline countries). [scope], when
  /// given, runs *first* in each pass: the rows of the view the user is looking
  /// at are worth cataloguing before the rest of the library, and the unscoped
  /// pass then resumes the backlog they are not part of.
  ///
  /// Serialized with [runPlaces]: a request that arrives mid-pass is queued,
  /// never dropped, and the eager pair always completes before any places pass
  /// so a coarse country write can never clobber a fine address. [stop] halts
  /// cooperatively between chunks.
  Future<void> run({int chunkSize = 200, CollectionWindowPredicate? scope}) {
    _pendingScope = scope;
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
  Future<void> _drain(int chunkSize) async {
    if (_draining) return;
    _draining = true;
    try {
      while (!_stopRequested && (_pendingRun || _pendingPlaces)) {
        if (_pendingRun) {
          _pendingRun = false;
          final scope = _pendingScope;
          _pendingScope = null;
          await _runCatalog(chunkSize, scope);
          if (!_stopRequested) await _runCountries(chunkSize, scope);
        }
        if (!_stopRequested && _pendingPlaces) {
          _pendingPlaces = false;
          if (await canLocate()) await _runPlaces(chunkSize);
        }
      }
    } finally {
      _draining = false;
      source.state = SourceState.ready;
    }
  }

  void stop() => _stopRequested = true;

  /// Runs the catalog pass, scoped rows first when [scope] is given.
  Future<void> _runCatalog(int chunkSize, CollectionWindowPredicate? scope) async {
    if (scope != null) {
      await _runCatalogPass(chunkSize, scope);
      if (_stopRequested) return;
    }
    await _runCatalogPass(chunkSize, null);
  }

  Future<void> _runCatalogPass(int chunkSize, CollectionWindowPredicate? scope) async {
    final predicate = scope ?? const CollectionWindowPredicate();
    final total = await database.countUncatalogued(predicate);
    if (total == 0) return;
    var after = LocalMediaDb.backlogStart;
    var done = 0;
    var stopCheckCount = 0;
    final pending = <CatalogMetadata>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveCatalogMetadata(Set.unmodifiable(pending));
      source.onCatalogMetadataChanged();
      pending.clear();
    }

    source.state = SourceState.cataloguing;
    source.setProgress(done: 0, total: total);
    while (!_stopRequested) {
      final page = await database.loadUncataloguedEntryIds(predicate: predicate, after: after, limit: chunkSize);
      if (page.isEmpty) break;
      after = page.last;
      for (final entry in await _materialize({for (final cursor in page) cursor.id})) {
        try {
          await catalogEntry(entry);
          if (entry.isCatalogued) pending.add(entry.catalogMetadata!);
        } catch (error, stack) {
          _log.w('paged catalog failed for entry id=${entry.id}', error, stack);
        } finally {
          entry.dispose();
        }
        if (pending.length >= TagMixin.commitCountThreshold) await flush();
        if (++stopCheckCount >= 100) {
          stopCheckCount = 0;
          if (_stopRequested) break;
        }
      }
      done += page.length;
      source.setProgress(done: done, total: total);
      // Cooperative yield between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }

  /// Runs the offline-country pass, scoped rows first when [scope] is given.
  Future<void> _runCountries(int chunkSize, CollectionWindowPredicate? scope) async {
    if (scope != null) {
      await _runCountriesPass(chunkSize, scope);
      if (_stopRequested) return;
    }
    await _runCountriesPass(chunkSize, null);
  }

  Future<void> _runCountriesPass(int chunkSize, CollectionWindowPredicate? scope) async {
    final predicate = scope ?? const CollectionWindowPredicate();
    var after = LocalMediaDb.backlogStart;
    var done = 0;
    final pending = <AddressDetails>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveAddresses(Set.unmodifiable(pending));
      source.onAddressMetadataChanged();
      pending.clear();
    }

    source.state = SourceState.locatingCountries;
    source.setProgress(done: 0, total: 0);
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
      done += page.length;
      source.setProgress(done: done, total: 0);
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
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
    var done = 0;
    final pending = <AddressDetails>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveAddresses(Set.unmodifiable(pending));
      source.onAddressMetadataChanged();
      pending.clear();
    }

    source.state = SourceState.locatingPlaces;
    source.setProgress(done: 0, total: 0);
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
      done += page.length;
      source.setProgress(done: done, total: 0);
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }
}
