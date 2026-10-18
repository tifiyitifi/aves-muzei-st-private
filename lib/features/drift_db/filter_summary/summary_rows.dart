/// Plain rows returned by the DB-backed filter summaries.
///
/// They mirror the legacy in-memory derivations (`rawAlbums`, `sortedTags`,
/// `sortedCountries/States/Places` + per-filter count/size/recent) without
/// materializing entries. `maxBestDate` serves date sorting; `recentId` batch
/// resolves through the existing `loadEntriesById` for cover thumbnails.
class AlbumSummaryRow {
  final String directory;
  final int count;
  final int sizeBytes;
  final int maxBestDate;
  final int recentId;

  /// Whether the album holds an image/video, mirroring `AvesEntry.isImage` and
  /// `isVideo` (which also counts an animated AVIF as a video). The albums grid
  /// groups by media kind on entry-free (paged) sources.
  final bool hasImage, hasVideo;

  /// Rows of the album with no catalog metadata row yet, reported by the album
  /// header's badge. Unlike the backlog itself this follows the summary's own
  /// scope, so trashed and hidden rows are not counted: the badge answers "what
  /// would cataloguing this album gain the user", not "what does a sweep have
  /// left".
  final int uncatalogued;

  const new({
    required this.directory,
    required this.count,
    required this.sizeBytes,
    required this.maxBestDate,
    required this.recentId,
    required this.hasImage,
    required this.hasVideo,
    required this.uncatalogued,
  });
}

class TagSummaryRow {
  final String tag;
  final int count;
  final int sizeBytes;
  final int maxBestDate;
  final int recentId;

  const new({
    required this.tag,
    required this.count,
    required this.sizeBytes,
    required this.maxBestDate,
    required this.recentId,
  });
}

class CountrySummaryRow {
  final String code;
  final String? name;
  final int count;
  final int sizeBytes;
  final int maxBestDate;
  final int recentId;

  const new({
    required this.code,
    required this.name,
    required this.count,
    required this.sizeBytes,
    required this.maxBestDate,
    required this.recentId,
  });
}

/// Grouped by `(countryCode, adminArea)`; the caller merges pairs into state
/// codes through `GeoStates`, mirroring `LocationMixin._getAreaByCode`.
class StateSummaryRow {
  final String? countryCode;
  final String adminArea;
  final int count;
  final int sizeBytes;
  final int maxBestDate;
  final int recentId;

  const new({
    required this.countryCode,
    required this.adminArea,
    required this.count,
    required this.sizeBytes,
    required this.maxBestDate,
    required this.recentId,
  });
}

class PlaceSummaryRow {
  final String place;
  final int count;
  final int sizeBytes;
  final int maxBestDate;
  final int recentId;

  const new({
    required this.place,
    required this.count,
    required this.sizeBytes,
    required this.maxBestDate,
    required this.recentId,
  });
}
