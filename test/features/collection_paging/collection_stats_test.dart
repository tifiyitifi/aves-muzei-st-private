import 'package:aves/features/collection_paging/stats/collection_stats.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/locale/calendar/calendar_utils.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/date.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';

/// The stats accumulator: the numbers a windowed scope folds from the database,
/// which must equal the ones the stats page derives from in-memory entries.
void main() {
  setUpAll(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  AvesEntry entry(
    int id, {
    int? sizeBytes = 5,
    int? durationMillis = 0,
    String path = '/album/1.jpg',
    String sourceMimeType = 'image/jpeg',
    int? sourceDateTakenMillis,
  }) =>
      AvesEntry(
        id: id,
        uri: 'content://$id',
        path: path,
        contentId: 100 + id,
        pageId: null,
        sourceMimeType: sourceMimeType,
        width: 10,
        height: 20,
        sourceRotationDegrees: 0,
        sizeBytes: sizeBytes,
        sourceTitle: 'title$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: sourceDateTakenMillis,
        durationMillis: durationMillis,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  CatalogMetadata metadata(
    int id, {
    String? mimeType,
    String? xmpSubjects,
    int rating = 0,
    double? latitude,
    double? longitude,
    int? dateMillis,
  }) =>
      CatalogMetadata(
        id: id,
        mimeType: mimeType,
        dateMillis: dateMillis,
        xmpSubjects: xmpSubjects,
        rating: rating,
        latitude: latitude,
        longitude: longitude,
      );

  test('the accumulator reads the catalogued face exactly like the entry', () {
    final meta = metadata(1, mimeType: 'image/heic', xmpSubjects: 'sunset;beach;', rating: 4, latitude: 48.85, longitude: 2.35);
    const address = AddressDetails(id: 1, countryName: 'France', countryCode: 'FR', adminArea: 'Ile-de-France', locality: 'Paris');
    final item = entry(1)..catalogMetadata = meta..addressDetails = address;

    final stats = (CollectionStatsAccumulator(ACalendar.gregorian)..add((entry: item, metadata: meta, address: address))).build();

    // The expectations are the entry's own getters, so the walk can never
    // diverge from an in-memory entry without failing here.
    expect(stats.entryCount, 1);
    expect(stats.totalSizeBytes, item.sizeBytes);
    expect(stats.totalDurationMillis, item.durationMillis);
    expect(stats.cataloguedCount, item.isCatalogued ? 1 : 0);
    expect(stats.withGpsCount, item.hasGps ? 1 : 0);
    expect(stats.entryCountPerMimeType[item.mimeType], 1);
    expect(stats.entryCountPerRating[item.rating], 1);
    expect(stats.entryCountPerAlbum[item.directory], 1);
    for (final tag in item.tags) {
      expect(stats.entryCountPerTag[tag], 1);
    }
    // Tags are split on `;` and empties dropped, exactly like `AvesEntry.tags`.
    expect(stats.entryCountPerTag.keys, item.tags);

    // Addresses: the page's own formatting, from the address's getters.
    expect(stats.entryCountPerCountry['${address.countryName}${LocationFilter.locationSeparator}${address.countryCode}'], 1);
    expect(stats.entryCountPerPlace[address.place], 1);
    final stateName = address.stateName;
    if (stateName != null) {
      expect(stats.entryCountPerState['$stateName${LocationFilter.locationSeparator}${address.stateCode}'], 1);
    }
  });

  test('an uncatalogued entry counts as uncatalogued, unrated and untyped', () {
    final item = entry(1, sourceMimeType: 'video/mp4', durationMillis: 3000);

    final stats = (CollectionStatsAccumulator(ACalendar.gregorian)..add((entry: item, metadata: null, address: null))).build();

    expect(stats.cataloguedCount, 0);
    expect(stats.withGpsCount, 0);
    expect(stats.entryCountPerMimeType, {'video/mp4': 1});
    expect(stats.entryCountPerRating[0], 1);
    expect(stats.entryCountPerTag, isEmpty);
    expect(stats.totalDurationMillis, 3000);
  });

  test('the rating map keeps a zero row at every step', () {
    final stats = CollectionStatsAccumulator(ACalendar.gregorian).build();
    expect(stats.entryCountPerRating.keys, [5, 4, 3, 2, 1, 0]);
    expect(stats.entryCountPerRating.values, everyElement(0));
  });

  group('histogram', () {
    // Local dates, built through the calendar's own day arithmetic, so the
    // buckets do not depend on the machine's timezone or DST.
    final calOps = ACalendar.gregorian.ops;

    CollectionStats statsOf(List<DateTime> dates) {
      final accumulator = CollectionStatsAccumulator(ACalendar.gregorian);
      var id = 1;
      for (final date in dates) {
        accumulator.add((entry: entry(id++, sourceDateTakenMillis: date.millisecondsSinceEpoch), metadata: null, address: null));
      }
      return accumulator.build();
    }

    test('a single day has nothing to chart', () {
      final day = DateTime(2024, 1, 1);
      final stats = statsOf([day, day.add(const Duration(hours: 1))]);
      expect(stats.histogram, isNull);
    });

    test('a short range buckets by day', () {
      final first = DateTime(2024, 1, 1);
      final last = calOps.addDaysToDate(first, 2);
      final stats = statsOf([first, last, last]);
      final histogram = stats.histogram!;
      expect(histogram.level, DateLevel.ymd);
      expect(histogram.entryCountPerDate, {
        DateTime(2024, 1, 1): 1,
        DateTime(2024, 1, 3): 2,
      });
      expect(histogram.firstDate, DateTime(2024, 1, 1));
      expect(histogram.lastDate, DateTime(2024, 1, 3));
    });

    test('a medium range buckets by month', () {
      final first = DateTime(2024, 1, 1);
      final last = calOps.addDaysToDate(first, 40);
      final stats = statsOf([first, last]);
      final histogram = stats.histogram!;
      expect(histogram.level, DateLevel.ym);
      expect(histogram.entryCountPerDate, {
        DateTime(2024, 1, 1): 1,
        DateTime(2024, 2, 1): 1,
      });
    });

    test('a long range buckets by year', () {
      final first = DateTime(2020, 5, 5);
      final last = calOps.addDaysToDate(first, 400);
      final stats = statsOf([first, last]);
      final histogram = stats.histogram!;
      expect(histogram.level, DateLevel.y);
      expect(histogram.entryCountPerDate, {
        DateTime(2020, 1, 1): 1,
        DateTime(2021, 1, 1): 1,
      });
    });

    test('undated entries chart nothing', () {
      final stats = statsOf([]);
      expect(stats.histogram, isNull);
    });
  });
}
