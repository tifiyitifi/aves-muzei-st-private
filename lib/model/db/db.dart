import 'dart:typed_data';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/drift_db/filter_summary/summary_rows.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/favourites.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/viewer/video_playback.dart';
import 'package:aves_model/aves_model.dart';

/// One position of a backlog sweep (the catalog/locate passes).
///
/// Sweeps advance album by album, so the position is the row's directory bucket
/// (empty when the directory is null, matching the sweep's ordering) plus its
/// id. A sweep that stops early resumes from here instead of re-walking the
/// rows it already finished.
typedef BacklogCursor = ({String directory, int id});

abstract class LocalMediaDb {
  /// The first position of a backlog sweep, before every row.
  static const BacklogCursor backlogStart = (directory: '', id: 0);
  int get nextId;

  Future<String> get path;

  Future<void> init();

  Future<int> dbFileSize();

  Future<void> reset();

  Future<void> removeIds(Set<int> ids, {Set<EntryDataType>? dataTypes});

  // entries

  Future<void> clearEntries();

  Future<Set<AvesEntry>> loadEntries({int? origin, String? directory});

  Future<Set<AvesEntry>> loadEntriesById(Set<int> ids);

  /// Loads entries by URI (bounded `IN` query, chunked).
  Future<Set<AvesEntry>> loadEntriesByUris(Set<String> uris);

  /// Loads entries by MediaStore content id (bounded `IN` query, chunked).
  Future<Set<AvesEntry>> loadEntriesByContentIds(Set<int> ids);

  /// Counts the entries matching the window predicate (same definition as
  /// [loadEntryWindow], so the total always matches a full walk of windows).
  Future<int> countEntries([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]);

  /// Loads one window of entries in collection order ([SortFactor] + whole-list
  /// [reverse]), for paged collection loading without full materialization.
  ///
  /// The optional section predicates restrict the window to one section,
  /// matching [loadSectionHeaders].
  Future<List<AvesEntry>> loadEntryWindow({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    String? directoryEquals,
    bool directoryEqualsNull = false,
    int? dateFromMillis,
    int? dateToMillis,
    int? ratingEquals,
    required SortFactor sort,
    required bool reverse,
    required int limit,
    required int offset,
  });

  /// One keyset page of the rows matching [predicate], in id order.
  ///
  /// Walks a whole scope without materializing it (the stats aggregate): every
  /// row is returned exactly once, in bounded chunks. [afterId] is exclusive,
  /// pass 0 to start.
  Future<List<AvesEntry>> loadWalkWindow({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    required int afterId,
    required int limit,
  });

  /// Loads one header per group of the window predicate, in display order.
  Future<List<SectionHeader>> loadSectionHeaders({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    required SectionGrouping grouping,
    required bool reverse,
  });

  /// Whether any entry hides behind a stack tile.
  ///
  /// A cheap probe that lets a view skip the stack filter entirely on a library
  /// without stacks (no burst pattern, no developed-raw pair).
  Future<bool> hasStackedEntries();

  /// Rebuilds the burst index after the configured burst patterns changed.
  Future<void> rebuildStackKeys();

  /// The stacks the tiles [ids] show, keyed by the tile's id.
  ///
  /// Each list starts with the tile itself and is ordered the way the legacy
  /// stack shows it (a burst by natural name, a developed image before its raws).
  /// Tiles with no hidden member are absent from the map.
  Future<Map<int, List<AvesEntry>>> loadStackMembers(Set<int> ids);

  /// Number of days holding matching entries: the calendar projection's total.
  Future<int> countDays({required CollectionWindowPredicate predicate});

  /// One row per day of the calendar projection, in day order, carrying the
  /// day's representative entry.
  Future<List<AvesEntry>> loadDayWindow({
    required CollectionWindowPredicate predicate,
    int? dateFromMillis,
    int? dateToMillis,
    required bool reverse,
    required int limit,
    required int offset,
  });

  /// Month headers of the calendar projection, each counting the days it holds.
  Future<List<SectionHeader>> loadDaySectionHeaders({
    required CollectionWindowPredicate predicate,
    required bool reverse,
  });

  /// The display aspect ratios of a section's rows, in collection order, as a
  /// compact channel for the mosaic layout.
  Future<Float32List> loadRatioChannel({
    required CollectionWindowPredicate predicate,
    String? directoryEquals,
    bool directoryEqualsNull,
    int? dateFromMillis,
    int? dateToMillis,
    int? ratingEquals,
    required SortFactor sort,
    required bool reverse,
  });

  /// Row index of the entry with [id] in the calendar projection, or -1 when it
  /// is not in the view.
  Future<int> countDaysBefore({
    required CollectionWindowPredicate predicate,
    required int id,
    required bool reverse,
  });

  /// The entries of each of [days], keyed by the day (a calendar tile's stack).
  Future<Map<DateTime, List<AvesEntry>>> loadDayMembers({
    required CollectionWindowPredicate predicate,
    required Set<DateTime> days,
    required bool reverse,
  });

  /// Global index of the entry with [id] in the collection order of
  /// [predicate], or -1 when it is not in the view.
  ///
  /// Resolved with the database's own ordering, so a viewer can open on an
  /// entry without loading a single window.
  Future<int> countEntriesBefore({
    required CollectionWindowPredicate predicate,
    required int id,
    required SortFactor sort,
    required bool reverse,
  });

  /// Count, total size and most recent `bestDate` of the entries matching
  /// [predicate] — the aggregate of a filter tile (album group, dynamic album,
  /// ...) without materializing its entries.
  Future<({int count, int sizeBytes, int maxBestDate})> aggregateEntries(CollectionWindowPredicate predicate);

  /// DB-backed filter summaries: per-group aggregates plus recent entry id,
  /// without materializing entries. Powers the filter grid pages (albums,
  /// tags, countries, states, places) for entry-free (paged) collections.
  Future<List<AlbumSummaryRow>> loadAlbumSummaryRows(SummaryExclusion exclusion);

  Future<List<TagSummaryRow>> loadTagSummaryRows(SummaryExclusion exclusion);

  Future<List<CountrySummaryRow>> loadCountrySummaryRows(SummaryExclusion exclusion);

  Future<List<StateSummaryRow>> loadStateSummaryRows(SummaryExclusion exclusion);

  Future<List<PlaceSummaryRow>> loadPlaceSummaryRows(SummaryExclusion exclusion);

  /// The scope's distinct mime types, catalogued mime first, mirroring
  /// `AvesEntry.mimeType`. Powers the search page's format filters on
  /// entry-free (paged) collections, where the entries cannot be scanned.
  Future<List<String>> loadMimeTypes(SummaryExclusion exclusion);

  Future<void> insertEntries(Set<AvesEntry> entries);

  Future<void> updateEntry(int id, AvesEntry entry);

  Future<Set<AvesEntry>> searchLiveEntries(String query, {int? limit});

  Future<Set<AvesEntry>> searchLiveDuplicates(int origin, Set<AvesEntry>? entries);

  // date taken

  Future<void> clearDates();

  Future<Map<int?, int?>> loadDates();

  // catalog metadata

  Future<void> clearCatalogMetadata();

  Future<Set<CatalogMetadata>> loadCatalogMetadata();

  Future<Set<CatalogMetadata>> loadCatalogMetadataById(Set<int> ids);

  Future<void> saveCatalogMetadata(Set<CatalogMetadata> metadataEntries);

  Future<void> updateCatalogMetadata(int id, CatalogMetadata? metadata);

  /// Counts entries missing catalog metadata rows (the catalog backlog),
  /// optionally limited to [predicate]'s scope.
  Future<int> countUncatalogued([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]);

  /// Keyset page over entries missing metadata rows, for the background
  /// catalog worker, in album-then-id order. [after] is exclusive (pass the
  /// start cursor to begin), and [predicate] limits the page to one scope so a
  /// view can be catalogued before the rest of the library.
  Future<List<BacklogCursor>> loadUncataloguedEntryIds({CollectionWindowPredicate predicate, required BacklogCursor after, required int limit});

  // address

  Future<void> clearAddresses();

  Future<Set<AddressDetails>> loadAddresses();

  Future<Set<AddressDetails>> loadAddressesById(Set<int> ids);

  Future<void> saveAddresses(Set<AddressDetails> addresses);

  Future<void> updateAddress(int id, AddressDetails? address);

  /// Keyset page over GPS entries missing address rows (the locate backlog).
  /// [afterId] is exclusive.
  Future<List<BacklogCursor>> loadUnaddressedGpsIds({CollectionWindowPredicate predicate, required BacklogCursor after, required int limit});

  /// Keyset page over GPS entries missing *fine* addresses (the locate-places
  /// backlog): rows with no address row, or a country-only row.
  /// [afterId] is exclusive.
  Future<List<BacklogCursor>> loadUnlocatedGpsIds({CollectionWindowPredicate predicate, required BacklogCursor after, required int limit});

  // vaults

  Future<void> clearVaults();

  Future<Set<VaultDetails>> loadAllVaults();

  Future<void> addVaults(Set<VaultDetails> rows);

  Future<void> updateVault(String oldName, VaultDetails row);

  Future<void> removeVaults(Set<VaultDetails> rows);

  // trash

  Future<void> clearTrashDetails();

  Future<Set<TrashDetails>> loadAllTrashDetails();

  Future<void> updateTrash(int id, TrashDetails? details);

  // favourites

  Future<void> clearFavourites();

  Future<Set<FavouriteRow>> loadAllFavourites();

  Future<void> addFavourites(Set<FavouriteRow> rows);

  Future<void> updateFavouriteId(int id, FavouriteRow row);

  Future<void> removeFavourites(Set<FavouriteRow> rows);

  // covers

  Future<void> clearCovers();

  Future<Set<CoverRow>> loadAllCovers();

  Future<void> addCovers(Set<CoverRow> rows);

  Future<void> updateCoverEntryId(int id, CoverRow row);

  Future<void> removeCovers(Set<CollectionFilter> filters);

  // dynamic albums

  Future<int> clearDynamicAlbums();

  Future<Set<DynamicAlbumRow>> loadAllDynamicAlbums();

  Future<void> addDynamicAlbums(Set<DynamicAlbumRow> rows);

  Future<void> removeDynamicAlbums(Set<String> names);

  // video playback

  Future<void> clearVideoPlayback();

  Future<Set<VideoPlaybackRow>> loadAllVideoPlayback();

  Future<VideoPlaybackRow?> loadVideoPlayback(int id);

  Future<void> addVideoPlayback(Set<VideoPlaybackRow> rows);

  Future<void> removeVideoPlayback(Set<int> ids);

  // debug

  Future<void> clearDebugLog();

  Future<List<String>> loadAllDebugLog();

  Future<void> addDebugLog(String message);
}
