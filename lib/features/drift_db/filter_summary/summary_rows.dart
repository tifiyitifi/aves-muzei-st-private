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

  const new({
    required this.directory,
    required this.count,
    required this.sizeBytes,
    required this.maxBestDate,
    required this.recentId,
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
