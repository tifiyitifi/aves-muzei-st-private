import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/drift_db/filter_summary/hidden_exclusion.dart';
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

abstract class LocalMediaDb {
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

  /// Loads one header per group of the window predicate, in display order.
  Future<List<SectionHeader>> loadSectionHeaders({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    required SectionGrouping grouping,
    required bool reverse,
  });

  /// DB-backed filter summaries: per-group aggregates plus recent entry id,
  /// without materializing entries. Powers the filter grid pages (albums,
  /// tags, countries, states, places) for entry-free (paged) collections.
  Future<List<AlbumSummaryRow>> loadAlbumSummaryRows(SummaryExclusion exclusion);

  Future<List<TagSummaryRow>> loadTagSummaryRows(SummaryExclusion exclusion);

  Future<List<CountrySummaryRow>> loadCountrySummaryRows(SummaryExclusion exclusion);

  Future<List<StateSummaryRow>> loadStateSummaryRows(SummaryExclusion exclusion);

  Future<List<PlaceSummaryRow>> loadPlaceSummaryRows(SummaryExclusion exclusion);

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

  /// Counts entries missing catalog metadata rows (the catalog backlog).
  Future<int> countUncatalogued();

  /// Keyset page over entries missing metadata rows, for the background
  /// catalog worker. [afterId] is exclusive.
  Future<List<int>> loadUncataloguedEntryIds({required int afterId, required int limit});

  // address

  Future<void> clearAddresses();

  Future<Set<AddressDetails>> loadAddresses();

  Future<Set<AddressDetails>> loadAddressesById(Set<int> ids);

  Future<void> saveAddresses(Set<AddressDetails> addresses);

  Future<void> updateAddress(int id, AddressDetails? address);

  /// Keyset page over GPS entries missing address rows (the locate backlog).
  /// [afterId] is exclusive.
  Future<List<int>> loadUnaddressedGpsIds({required int afterId, required int limit});

  /// Keyset page over GPS entries missing *fine* addresses (the locate-places
  /// backlog): rows with no address row, or a country-only row.
  /// [afterId] is exclusive.
  Future<List<int>> loadUnlocatedGpsIds({required int afterId, required int limit});

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
