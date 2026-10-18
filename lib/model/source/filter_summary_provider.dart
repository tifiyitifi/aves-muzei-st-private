import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/filters.dart';

/// Sync read surface for DB-backed filter summaries, served to entry-free
/// (paged) collections.
///
/// All values come from preloaded per-domain caches; unknown filters read as
/// empty/zero/null until their domain loads. Implemented by the fork-only
/// paging slice; the legacy in-memory path never sets a provider.
abstract class FilterSummaryProvider {
  /// Preloads the albums domain, so [albumDirectories] and per-album
  /// aggregates serve without a full collection load. Used by pick dialogs
  /// on entry-free (paged) sources.
  Future<void> ensureAlbums();

  /// Preloads the tags domain, so [tags] and per-tag aggregates serve without
  /// a full collection load. Used by pick dialogs on entry-free sources.
  Future<void> ensureTags();

  /// Preloads the locations domain, so [countries]/[states]/[places] serve
  /// without a full collection load.
  Future<void> ensureLocations();

  /// Preloads the formats domain, so [mimeTypes] serves without a full
  /// collection load. Used by the search page on entry-free sources.
  Future<void> ensureMimes();

  List<String> get albumDirectories;

  List<String> get tags;

  /// The scope's mime types, ascending, mirroring `AvesEntry.mimeType`.
  List<String> get mimeTypes;

  /// `'name;code'` display strings, mirroring `LocationMixin` derivations.
  List<String> get countries;

  List<String> get states;

  List<String> get places;

  int albumCount(AlbumBaseFilter filter);

  int albumSize(AlbumBaseFilter filter);

  int albumMaxBestDate(AlbumBaseFilter filter);

  AvesEntry? albumRecentEntry(AlbumBaseFilter filter);

  /// Whether the album holds an image/video, mirroring `AvesEntry.isImage` and
  /// `isVideo`. The albums grid groups by media kind on entry-free sources.
  ({bool hasImage, bool hasVideo}) albumMediaKinds(AlbumBaseFilter filter);

  int tagCount(TagBaseFilter filter);

  int tagSize(TagBaseFilter filter);

  int tagMaxBestDate(TagBaseFilter filter);

  AvesEntry? tagRecentEntry(TagBaseFilter filter);

  int locationCount(LocationFilter filter);

  int locationSize(LocationFilter filter);

  int locationMaxBestDate(LocationFilter filter);

  AvesEntry? locationRecentEntry(LocationFilter filter);

  int count(CollectionFilter filter);

  int size(CollectionFilter filter);

  AvesEntry? recentEntry(CollectionFilter filter);

  AvesEntry? coverEntry(CollectionFilter filter);
}
