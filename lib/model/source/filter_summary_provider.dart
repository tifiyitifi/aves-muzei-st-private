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
  List<String> get albumDirectories;

  List<String> get tags;

  /// `'name;code'` display strings, mirroring `LocationMixin` derivations.
  List<String> get countries;

  List<String> get states;

  List<String> get places;

  int albumCount(AlbumBaseFilter filter);

  int albumSize(AlbumBaseFilter filter);

  int albumMaxBestDate(AlbumBaseFilter filter);

  AvesEntry? albumRecentEntry(AlbumBaseFilter filter);

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
