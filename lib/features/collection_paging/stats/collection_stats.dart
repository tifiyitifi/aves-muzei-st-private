import 'package:aves/locale/aves_locale.dart';
import 'package:aves/locale/calendar/calendar_utils.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/date.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/utils/time_utils.dart';

/// One row of a stats walk: the entry plus the metadata rows that define its
/// catalogued face.
///
/// The catalogued face travels next to the entry instead of being attached to
/// it: `AvesEntry.catalogMetadata` evicts the image cache and clears the
/// platform decoders, which a walk of a whole library must not do once per row.
typedef StatsRow = ({AvesEntry entry, CatalogMetadata? metadata, AddressDetails? address});

/// The date histogram's data of a windowed collection.
///
/// Normalized exactly like the histogram widget normalizes its entries, so the
/// chart, its level and its axis are the ones an in-memory collection shows.
class DateHistogramData {
  final DateLevel level;
  final DateTime firstDate, lastDate;
  final Map<DateTime, int> entryCountPerDate;

  const new({
    required this.level,
    required this.firstDate,
    required this.lastDate,
    required this.entryCountPerDate,
  });
}

/// Statistics of a collection, accumulated without holding its entries.
///
/// Field for field what the stats page derives from an in-memory collection: a
/// windowed scope cannot be walked in memory, so [CollectionStatsAccumulator]
/// folds its rows in bounded chunks instead. Every map is a library's
/// cardinality (albums, tags, places, days), never its size.
class CollectionStats {
  final int entryCount;
  final int totalSizeBytes, totalDurationMillis;

  /// Entries carrying catalog metadata, and those among them with GPS
  /// coordinates: the location indicator's counts.
  final int cataloguedCount, withGpsCount;

  final Map<String, int> entryCountPerCountry, entryCountPerState, entryCountPerPlace;
  final Map<String, int> entryCountPerTag, entryCountPerAlbum, entryCountPerMimeType;
  final Map<int, int> entryCountPerRating;

  /// Null when the scope holds no dated entries, or spans less than two days:
  /// the histogram has nothing to chart then, and stays hidden.
  final DateHistogramData? histogram;

  /// The empty aggregate: a scope whose walk failed renders its normal empty
  /// state rather than a wrong one.
  static const empty = CollectionStats(
    entryCount: 0,
    totalSizeBytes: 0,
    totalDurationMillis: 0,
    cataloguedCount: 0,
    withGpsCount: 0,
    entryCountPerCountry: {},
    entryCountPerState: {},
    entryCountPerPlace: {},
    entryCountPerTag: {},
    entryCountPerAlbum: {},
    entryCountPerMimeType: {},
    entryCountPerRating: {},
  );

  const new({
    required this.entryCount,
    required this.totalSizeBytes,
    required this.totalDurationMillis,
    required this.cataloguedCount,
    required this.withGpsCount,
    required this.entryCountPerCountry,
    required this.entryCountPerState,
    required this.entryCountPerPlace,
    required this.entryCountPerTag,
    required this.entryCountPerAlbum,
    required this.entryCountPerMimeType,
    required this.entryCountPerRating,
    this.histogram,
  });
}

/// Folds stats rows into a [CollectionStats].
///
/// The calendar is injected rather than read from the settings: the histogram's
/// buckets depend on it, and the walk must normalize every date the way the
/// settings would when the page is opened.
class CollectionStatsAccumulator {
  final ACalendar calendar;

  final Map<String, int> _entryCountPerCountry = {}, _entryCountPerState = {}, _entryCountPerPlace = {};
  final Map<String, int> _entryCountPerTag = {}, _entryCountPerAlbum = {}, _entryCountPerMimeType = {};
  final Map<int, int> _entryCountPerRating = {};

  /// Buckets of every level, so the level the range calls for is available once
  /// the walk ends: the range is only known then, and a second pass would cost
  /// the whole scope again. Each map is bounded by its own granularity, so the
  /// three together stay tiny.
  final Map<DateTime, int> _perDay = {}, _perMonth = {}, _perYear = {};

  int _entryCount = 0;
  int _totalSizeBytes = 0;
  int _totalDurationMillis = 0;
  int _cataloguedCount = 0;
  int _withGpsCount = 0;
  DateTime? _firstDate, _lastDate;

  new(this.calendar);

  void add(StatsRow row) {
    final entry = row.entry;
    final metadata = row.metadata;
    final address = row.address;

    _entryCount++;
    _totalSizeBytes += entry.sizeBytes ?? 0;
    _totalDurationMillis += entry.durationMillis ?? 0;

    // The next three lines are the exact expressions `AvesEntry.isCatalogued`,
    // `hasGps`, `rating`, `tags` and `mimeType` evaluate on an entry carrying
    // this metadata; a test pins them against such an entry.
    if (metadata != null) {
      _cataloguedCount++;
      if ((metadata.latitude ?? 0) != 0 || (metadata.longitude ?? 0) != 0) _withGpsCount++;
    }
    final rating = metadata?.rating ?? 0;
    final mimeType = metadata?.mimeType ?? entry.sourceMimeType;
    final tags = metadata?.xmpSubjects?.split(';').where((tag) => tag.isNotEmpty).toSet() ?? const <String>{};

    if (address != null) {
      var country = address.countryName;
      if (country != null && country.isNotEmpty) {
        country += '${LocationFilter.locationSeparator}${address.countryCode}';
        _entryCountPerCountry.update(country, (v) => v + 1, ifAbsent: () => 1);
      }
      var state = address.stateName;
      if (state != null && state.isNotEmpty) {
        state += '${LocationFilter.locationSeparator}${address.stateCode}';
        _entryCountPerState.update(state, (v) => v + 1, ifAbsent: () => 1);
      }
      final place = address.place;
      if (place != null && place.isNotEmpty) {
        _entryCountPerPlace.update(place, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    for (final tag in tags) {
      _entryCountPerTag.update(tag, (v) => v + 1, ifAbsent: () => 1);
    }

    final album = entry.directory;
    if (album != null) {
      _entryCountPerAlbum.update(album, (v) => v + 1, ifAbsent: () => 1);
    }

    _entryCountPerRating.update(rating, (v) => v + 1, ifAbsent: () => 1);
    _entryCountPerMimeType.update(mimeType, (v) => v + 1, ifAbsent: () => 1);

    final date = entry.bestDate;
    if (date != null) {
      if (_firstDate == null || date.isBefore(_firstDate!)) _firstDate = date;
      if (_lastDate == null || date.isAfter(_lastDate!)) _lastDate = date;
      final calOps = calendar.ops;
      _perDay.update(calOps.dateOnly(date), (v) => v + 1, ifAbsent: () => 1);
      _perMonth.update(calOps.monthDateOnly(date), (v) => v + 1, ifAbsent: () => 1);
      _perYear.update(calOps.yearDateOnly(date), (v) => v + 1, ifAbsent: () => 1);
    }
  }

  CollectionStats build() {
    return CollectionStats(
      entryCount: _entryCount,
      totalSizeBytes: _totalSizeBytes,
      totalDurationMillis: _totalDurationMillis,
      cataloguedCount: _cataloguedCount,
      withGpsCount: _withGpsCount,
      entryCountPerCountry: _entryCountPerCountry,
      entryCountPerState: _entryCountPerState,
      entryCountPerPlace: _entryCountPerPlace,
      entryCountPerTag: _entryCountPerTag,
      entryCountPerAlbum: _entryCountPerAlbum,
      entryCountPerMimeType: _entryCountPerMimeType,
      // The page presets one row per rating, so an unrated collection still
      // reports a zero at every step.
      entryCountPerRating: {for (var rating = 5; rating >= 0; rating--) rating: 0}..addAll(_entryCountPerRating),
      histogram: _buildHistogram(),
    );
  }

  DateHistogramData? _buildHistogram() {
    final first = _firstDate, last = _lastDate;
    if (first == null || last == null) return null;
    // Same rule as the histogram widget: a single day is not a chart.
    final rangeDays = last.difference(first).inHumanDays;
    if (rangeDays <= 1) return null;

    final calOps = calendar.ops;
    final DateLevel level;
    final Map<DateTime, int> entryCountPerDate;
    final DateTime Function(DateTime) normalizeDate;
    if (rangeDays <= calendar.maxDaysInMonth) {
      level = DateLevel.ymd;
      entryCountPerDate = _perDay;
      normalizeDate = calOps.dateOnly;
    } else if (rangeDays <= calendar.maxDaysInYear) {
      level = DateLevel.ym;
      entryCountPerDate = _perMonth;
      normalizeDate = calOps.monthDateOnly;
    } else {
      level = DateLevel.y;
      entryCountPerDate = _perYear;
      normalizeDate = calOps.yearDateOnly;
    }
    return DateHistogramData(
      level: level,
      firstDate: normalizeDate(first),
      lastDate: normalizeDate(last),
      entryCountPerDate: entryCountPerDate,
    );
  }
}
