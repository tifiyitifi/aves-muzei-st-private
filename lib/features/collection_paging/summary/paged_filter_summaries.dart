import 'dart:async';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/filter_summary/summary_rows.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/geo/states.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/container.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/source/album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/filter_summary_provider.dart';
import 'package:aves/model/source/location/country.dart';
import 'package:aves/model/source/location/place.dart';
import 'package:aves/model/source/location/state.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';

const _log = AreaKeyLog('log.collection_paging');

/// Domains load independently: albums eagerly (drawer + albums page), tags and
/// locations on first touch.
enum SummaryDomain { albums, tags, locations, mime }

/// DB-backed [FilterSummaryProvider] for entry-free (paged) collections.
///
/// Per-domain caches fill once via [ensureLoaded] and serve every sync
/// getter. Touching a getter for an unloaded domain schedules its load and
/// fires the matching `ChangedEvent` on completion, so the filter grid pages
/// rebuild with zero widget changes. Cover entries (pinned + recent) batch
/// resolve through the existing `loadEntriesById`, chunked so huge libraries
/// stay bounded.
class PagedFilterSummaries implements FilterSummaryProvider {
  final CollectionSource source;
  final LocalMediaDb database;
  final Set<CollectionFilter> Function() hiddenFilters;
  final Set<String> Function() lockedVaultDirs;

  /// Whether the collection is still being imported; the source must stay in
  /// `loading` until it is done, no matter how the summary loads settle.
  final bool Function()? isImporting;

  new({
    required this.source,
    LocalMediaDb? database,
    required this.hiddenFilters,
    required this.lockedVaultDirs,
    this.isImporting,
  }) : database = database ?? localMediaDb;

  /// Settles the source state, respecting an import still writing rows.
  void _settleState() {
    final importing = isImporting?.call() ?? false;
    source.state = importing ? SourceState.loading : SourceState.ready;
  }

  Map<String, AlbumSummaryRow> _albums = {};
  Map<String, TagSummaryRow> _tags = {};
  Map<String, CountrySummaryRow> _countries = {};
  Map<String, StateSummaryRow> _states = {};
  Map<String, PlaceSummaryRow> _places = {};
  List<String> _mimeTypes = [];
  Map<String, AvesEntry> _recentByFilterKey = {};

  /// Aggregates for container filters (album/tag groups, dynamic albums) that
  /// the per-album/per-tag rows cannot answer, because a group is a *union*
  /// (summing members would double-count overlapping entries). Computed from
  /// the database on first touch, keyed by [CollectionFilter.key].
  Map<String, ({int count, int sizeBytes, int maxBestDate})> _containers = {};
  final Set<String> _containerLoading = {};

  final Set<SummaryDomain> _loaded = {};
  final Set<SummaryDomain> _loading = {};
  int _pendingLoads = 0;

  /// Reloads already-loaded domains (their rows may have changed); loads
  /// albums when nothing is loaded yet.
  Future<void> reload() async {
    if (_loaded.isEmpty) {
      await ensureLoaded(SummaryDomain.albums);
      return;
    }
    final domains = Set.of(_loaded);
    invalidate();
    for (final domain in domains) {
      await ensureLoaded(domain);
    }
  }

  /// Drops every cache and disposes cached entries.
  void invalidate() {
    _albums = {};
    _tags = {};
    _countries = {};
    _states = {};
    _places = {};
    _mimeTypes = [];
    _containers = {};
    // Values may be shared between filters: dispose by identity.
    final seen = <AvesEntry>{};
    for (final entry in _recentByFilterKey.values) {
      if (seen.add(entry)) entry.dispose();
    }
    _recentByFilterKey = {};
    _loaded.clear();
  }

  /// Drops every cache and disposes cached entries. The lens calls this on
  /// morph and dispose, where the legacy path takes over.
  void dispose() => invalidate();

  @override
  Future<void> ensureAlbums() => ensureLoaded(SummaryDomain.albums);

  @override
  Future<void> ensureTags() => ensureLoaded(SummaryDomain.tags);

  @override
  Future<void> ensureLocations() => ensureLoaded(SummaryDomain.locations);

  @override
  Future<void> ensureMimes() => ensureLoaded(SummaryDomain.mime);

  Future<void> ensureLoaded(SummaryDomain domain) async {
    if (_loaded.contains(domain) || _loading.contains(domain)) return;
    _loading.add(domain);
    _pendingLoads++;
    source.state = SourceState.loading;
    try {
      final exclusion = buildSummaryExclusion(hidden: hiddenFilters(), lockedVaultDirs: lockedVaultDirs());
      switch (domain) {
        case SummaryDomain.albums:
          await _loadAlbums(exclusion);
        case SummaryDomain.tags:
          await _loadTags(exclusion);
        case SummaryDomain.locations:
          await _loadLocations(exclusion);
        case SummaryDomain.mime:
          await _loadMimes(exclusion);
      }
      _loaded.add(domain);
      _fire(domain);
    } catch (error, stack) {
      _log.e('summary load failed for $domain', error, stack);
    } finally {
      _loading.remove(domain);
      _pendingLoads--;
      if (_pendingLoads == 0) _settleState();
    }
  }

  void _fire(SummaryDomain domain) {
    switch (domain) {
      case SummaryDomain.albums:
        source.eventBus.fire(AlbumsChangedEvent());
      case SummaryDomain.tags:
        source.eventBus.fire(TagsChangedEvent());
      case SummaryDomain.locations:
        source.eventBus.fire(CountriesChangedEvent());
        source.eventBus.fire(StatesChangedEvent());
        source.eventBus.fire(PlacesChangedEvent());
      case SummaryDomain.mime:
        // The format list has no domain event: the search page awaits
        // [ensureMimes] itself and rebuilds its own row.
        break;
    }
  }

  void _kick(SummaryDomain domain) {
    if (_loaded.contains(domain) || _loading.contains(domain)) return;
    unawaited(ensureLoaded(domain));
  }

  Future<void> _loadAlbums(SummaryExclusion exclusion) async {
    final rows = await database.loadAlbumSummaryRows(exclusion);
    _albums = {for (final row in rows) row.directory: row};
    final filters = _albums.keys.map((dir) => StoredAlbumFilter(dir, null)).toList();
    await _resolveCovers(filters, {for (final row in rows) StoredAlbumFilter(row.directory, null).key: row.recentId});
  }

  Future<void> _loadTags(SummaryExclusion exclusion) async {
    final rows = await database.loadTagSummaryRows(exclusion);
    _tags = {for (final row in rows) row.tag: row};
    final filters = _tags.keys.map(TagFilter.new).toList();
    await _resolveCovers(filters, {for (final row in rows) TagFilter(row.tag).key: row.recentId});
  }

  Future<void> _loadLocations(SummaryExclusion exclusion) async {
    final countries = await database.loadCountrySummaryRows(exclusion);
    _countries = {for (final row in countries) row.code: row};
    final states = await database.loadStateSummaryRows(exclusion);
    _states = {for (final row in states) '${row.countryCode}\x1f${row.adminArea}': row};
    final places = await database.loadPlaceSummaryRows(exclusion);
    _places = {for (final row in places) row.place: row};

    final filters = <LocationFilter>[
      for (final row in countries) LocationFilter(LocationLevel.country, _nameAndCode(row.name, row.code)),
      for (final kv in _mergedStates().entries) LocationFilter(LocationLevel.state, _nameAndCode(kv.value, kv.key)),
      for (final row in places) LocationFilter(LocationLevel.place, row.place),
    ];
    await _resolveCovers(filters, {
      for (final row in countries) LocationFilter(LocationLevel.country, _nameAndCode(row.name, row.code)).key: row.recentId,
      for (final row in states)
        LocationFilter(LocationLevel.state, _nameAndCode(_stateName(row), _stateCode(row) ?? '')).key: row.recentId,
      for (final row in places) LocationFilter(LocationLevel.place, row.place).key: row.recentId,
    });
  }

  Future<void> _loadMimes(SummaryExclusion exclusion) async {
    _mimeTypes = await database.loadMimeTypes(exclusion);
  }

  /// Resolves pinned covers plus recent entries for [filters] in bounded
  /// chunks, attaching catalogued dates so `bestDate` keeps working. A pinned
  /// cover wins over the recent entry for its filter.
  Future<void> _resolveCovers<T extends CollectionFilter>(List<T> filters, Map<String, int> recentIdByFilterKey) async {
    final pinnedByKey = <String, int?>{for (final filter in filters) filter.key: covers.of(filter)?.entryId};
    final keysById = <int, List<String>>{};
    for (final filter in filters) {
      final key = filter.key;
      for (final id in [pinnedByKey[key], recentIdByFilterKey[key]]) {
        if (id != null) (keysById[id] ??= []).add(key);
      }
    }
    if (keysById.isEmpty) return;

    final dates = await database.loadDates();
    for (final slice in keysById.keys.slices(500)) {
      final entries = await database.loadEntriesById(slice.toSet());
      for (final entry in entries) {
        entry.catalogDateMillis = dates[entry.id];
        for (final key in keysById[entry.id] ?? const <String>[]) {
          final current = _recentByFilterKey[key];
          if (current == null || entry.id == pinnedByKey[key]) {
            _recentByFilterKey[key] = entry;
          }
        }
      }
    }
  }

  static String _nameAndCode(String? name, String code) => '${name != null && name.isNotEmpty ? name : code}${LocationFilter.locationSeparator}$code';

  /// Merges `(countryCode, adminArea)` pairs into state codes, mirroring
  /// `LocationMixin._getAreaByCode` (last pair wins).
  Map<String, String> _mergedStates() {
    final namesByCode = <String, String>{};
    for (final row in _states.values) {
      final name = _stateName(row);
      final code = _stateCode(row);
      if (name != null && code != null) namesByCode[code] = name;
    }
    return namesByCode;
  }

  static String? _stateName(StateSummaryRow row) {
    final countryCode = row.countryCode;
    if (countryCode == null || !GeoStates.stateCodesByCountryCode.containsKey(countryCode)) return null;
    return row.adminArea;
  }

  static String? _stateCode(StateSummaryRow row) {
    final name = _stateName(row);
    return name != null ? GeoStates.stateCodeByName[name] : null;
  }

  // lists

  @override
  List<String> get albumDirectories {
    _kick(SummaryDomain.albums);
    return _albums.keys.toList();
  }

  @override
  List<String> get tags {
    _kick(SummaryDomain.tags);
    return _tags.keys.toList()..sort(compareAsciiUpperCaseNatural);
  }

  @override
  List<String> get countries {
    _kick(SummaryDomain.locations);
    return _countries.values.map((r) => _nameAndCode(r.name, r.code)).toList()..sort(compareAsciiUpperCase);
  }

  @override
  List<String> get states {
    _kick(SummaryDomain.locations);
    return _mergedStates().entries.map((kv) => _nameAndCode(kv.value, kv.key)).toList()..sort(compareAsciiUpperCase);
  }

  @override
  List<String> get places {
    _kick(SummaryDomain.locations);
    return _places.keys.toList()..sort(compareAsciiUpperCase);
  }

  @override
  List<String> get mimeTypes {
    _kick(SummaryDomain.mime);
    return _mimeTypes;
  }

  // per-filter aggregates

  @override
  int albumCount(AlbumBaseFilter filter) {
    if (filter is StoredAlbumFilter) return _albums[filter.album]?.count ?? 0;
    return _container(filter)?.count ?? 0;
  }

  @override
  int albumSize(AlbumBaseFilter filter) {
    if (filter is StoredAlbumFilter) return _albums[filter.album]?.sizeBytes ?? 0;
    return _container(filter)?.sizeBytes ?? 0;
  }

  @override
  int albumMaxBestDate(AlbumBaseFilter filter) {
    if (filter is StoredAlbumFilter) return _albums[filter.album]?.maxBestDate ?? 0;
    return _container(filter)?.maxBestDate ?? 0;
  }

  /// Rows of [directory] still missing catalog metadata, for the album header
  /// badge. Zero while the albums domain is unloaded, which the badge reads as
  /// "nothing to do".
  ///
  /// Reads the cache without kicking a load: a paged lens loads the albums
  /// domain when it enters, and the badge is built from a header, where
  /// scheduling a load would mutate source state mid-build.
  int albumUncatalogued(String directory) => _albums[directory]?.uncatalogued ?? 0;

  @override
  AvesEntry? albumRecentEntry(AlbumBaseFilter filter) => filter is StoredAlbumFilter || _isContainer(filter) ? _recentByFilterKey[filter.key] : null;

  @override
  ({bool hasImage, bool hasVideo}) albumMediaKinds(AlbumBaseFilter filter) {
    _kick(SummaryDomain.albums);
    return _mediaKinds(filter, {});
  }

  /// The kinds an album holds, unioned over a container's members: a group of
  /// albums holds what its albums hold, exactly like the legacy scan of its
  /// entries. A member the per-album rows cannot answer (a tag or query filter
  /// inside a group) contributes nothing, so such a group can read as mixed.
  ({bool hasImage, bool hasVideo}) _mediaKinds(CollectionFilter filter, Set<String> visited) {
    if (filter is StoredAlbumFilter) {
      final row = _albums[filter.album];
      return (hasImage: row?.hasImage ?? false, hasVideo: row?.hasVideo ?? false);
    }
    if (filter is ContainerFilter && visited.add(filter.key)) {
      var hasImage = false, hasVideo = false;
      for (final inner in filter.innerFilters) {
        final kinds = _mediaKinds(inner, visited);
        hasImage = hasImage || kinds.hasImage;
        hasVideo = hasVideo || kinds.hasVideo;
      }
      return (hasImage: hasImage, hasVideo: hasVideo);
    }
    return (hasImage: false, hasVideo: false);
  }

  @override
  int tagCount(TagBaseFilter filter) {
    if (filter is TagFilter) return _tags[filter.tag]?.count ?? 0;
    return _container(filter)?.count ?? 0;
  }

  @override
  int tagSize(TagBaseFilter filter) {
    if (filter is TagFilter) return _tags[filter.tag]?.sizeBytes ?? 0;
    return _container(filter)?.sizeBytes ?? 0;
  }

  @override
  int tagMaxBestDate(TagBaseFilter filter) {
    if (filter is TagFilter) return _tags[filter.tag]?.maxBestDate ?? 0;
    return _container(filter)?.maxBestDate ?? 0;
  }

  @override
  AvesEntry? tagRecentEntry(TagBaseFilter filter) => filter is TagFilter || _isContainer(filter) ? _recentByFilterKey[filter.key] : null;

  /// A container filter (group or dynamic album) whose aggregate the per-filter
  /// rows cannot answer.
  static bool _isContainer(CollectionFilter filter) => filter is AlbumGroupFilter || filter is TagGroupFilter || filter is DynamicAlbumFilter;

  /// Cached aggregate for [filter], kicking a one-shot database computation on
  /// the first miss. Returns null (reads as zero) while it is in flight or when
  /// the filter is not expressible in SQL — the same "unknown reads empty"
  /// contract as the other domains.
  ({int count, int sizeBytes, int maxBestDate})? _container(CollectionFilter filter) {
    if (!_isContainer(filter)) return null;
    final key = filter.key;
    final cached = _containers[key];
    if (cached != null) return cached;
    if (_containerLoading.add(key)) {
      final predicate = predicateForFilters({filter});
      if (predicate == null) {
        _containerLoading.remove(key);
        return null;
      }
      _pendingLoads++;
      source.state = SourceState.loading;
      unawaited(
        _resolveContainer(filter, key, predicate).whenComplete(() {
          _containerLoading.remove(key);
          _pendingLoads--;
          if (_pendingLoads == 0) _settleState();
        }),
      );
    }
    return null;
  }

  Future<void> _resolveContainer(CollectionFilter filter, String key, CollectionWindowPredicate predicate) async {
    try {
      final aggregate = await database.aggregateEntries(predicate);
      _containers[key] = aggregate;
      // A cover keeps the group/dynamic-album tile recognizable.
      final window = await database.loadEntryWindow(predicate: predicate, sort: SortFactor.date, reverse: false, limit: 1, offset: 0);
      if (window.isNotEmpty) _recentByFilterKey[key] = window.first;
      if (filter is TagBaseFilter) {
        source.eventBus.fire(TagsChangedEvent());
      } else {
        source.eventBus.fire(AlbumsChangedEvent());
      }
    } catch (error, stack) {
      _log.e('container aggregate failed for ${filter.key}', error, stack);
    }
  }

  @override
  int locationCount(LocationFilter filter) => _locationRow(filter)?.count ?? 0;

  @override
  int locationSize(LocationFilter filter) => _locationRow(filter)?.sizeBytes ?? 0;

  @override
  int locationMaxBestDate(LocationFilter filter) => _locationRow(filter)?.maxBestDate ?? 0;

  @override
  AvesEntry? locationRecentEntry(LocationFilter filter) => _recentByFilterKey[filter.key];

  ({int count, int sizeBytes, int maxBestDate})? _locationRow(LocationFilter filter) {
    switch (filter.level) {
      case .country:
        final code = filter.code;
        if (code == null) return null;
        final row = _countries[code];
        return row == null ? null : (count: row.count, sizeBytes: row.sizeBytes, maxBestDate: row.maxBestDate);
      case .state:
        final code = filter.code;
        if (code == null) return null;
        final pair = _states.values.firstWhereOrNull((r) => _stateCode(r) == code);
        return pair == null ? null : (count: pair.count, sizeBytes: pair.sizeBytes, maxBestDate: pair.maxBestDate);
      case .place:
        final row = _places[filter.place];
        return row == null ? null : (count: row.count, sizeBytes: row.sizeBytes, maxBestDate: row.maxBestDate);
    }
  }

  // dispatch

  @override
  int count(CollectionFilter filter) {
    switch (filter) {
      case AlbumBaseFilter f:
        return albumCount(f);
      case LocationFilter f:
        return locationCount(f);
      case TagBaseFilter f:
        return tagCount(f);
    }
    return 0;
  }

  @override
  int size(CollectionFilter filter) {
    switch (filter) {
      case AlbumBaseFilter f:
        return albumSize(f);
      case LocationFilter f:
        return locationSize(f);
      case TagBaseFilter f:
        return tagSize(f);
    }
    return 0;
  }

  @override
  AvesEntry? recentEntry(CollectionFilter filter) {
    switch (filter) {
      case AlbumBaseFilter f:
        return albumRecentEntry(f);
      case LocationFilter f:
        return locationRecentEntry(f);
      case TagBaseFilter f:
        return tagRecentEntry(f);
    }
    return null;
  }

  @override
  AvesEntry? coverEntry(CollectionFilter filter) {
    if (filter is StoredAlbumFilter && vaults.isLocked(filter.album)) return null;
    final pinned = covers.of(filter)?.entryId;
    if (pinned != null) {
      final cached = _recentByFilterKey[filter.key];
      if (cached != null && cached.id == pinned) return cached;
      // Pinned entry not in the batch (e.g. set after the domain loaded):
      // fall through to the recent entry rather than stalling the tile.
    }
    return recentEntry(filter);
  }
}
