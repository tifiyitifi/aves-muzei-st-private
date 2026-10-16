import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/query/shuffle_permutation.dart';
import 'package:aves/features/collection_paging/view/paged_widget_candidates.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Home-widget entry resolution: a paged collection yields a single row (most
/// recent, or a seeded-permutation random pick) instead of a full load; small
/// or unsupported scopes keep the legacy path (`handled: false`).
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  late AppDatabase db;
  late DriftLocalMediaDb database;

  setUp(() async {
    await setUpServices();
    await collectionPagingPrefs.init();
    await collectionPagingPrefs.setEngine(CollectionEngine.auto);
    db = AppDatabase(NativeDatabase.memory());
    database = DriftLocalMediaDb(database: db);
    await database.init();
  });

  tearDown(() async {
    await setUpServices();
    await db.close();
  });

  AvesEntry entry(int id, {String dir = '/album', int dateTaken = 0}) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  group('PagedWidgetCandidates', () {
    test('most recent reads the first row of the collection order', () async {
      await database.insertEntries({entry(1, dateTaken: 100), entry(2, dateTaken: 300), entry(3, dateTaken: 200)});
      await collectionPagingPrefs.setLargeThreshold(2);

      final resolution = await PagedWidgetCandidates.resolve(filters: {}, mostRecent: true, database: database);
      expect(resolution.handled, isTrue);
      expect(resolution.entry?.id, 2);
    });

    test('random picks a single row through the seeded permutation', () async {
      await database.insertEntries({entry(1, dateTaken: 100), entry(2, dateTaken: 300), entry(3, dateTaken: 200)});
      await collectionPagingPrefs.setLargeThreshold(2);

      const seed = 42;
      final resolution = await PagedWidgetCandidates.resolve(filters: {}, mostRecent: false, shuffleSeed: seed, database: database);
      expect(resolution.handled, isTrue);
      // The pick is the ordered row at the permutation's first virtual position.
      final total = await database.countEntries();
      final expectedOffset = ShufflePermutation(seed, total).forward(0);
      final ordered = await database.loadEntryWindow(sort: SortFactor.date, reverse: false, limit: total, offset: 0);
      expect(resolution.entry?.id, ordered[expectedOffset].id);
    });

    test('keeps the legacy path below the threshold', () async {
      await database.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(100);

      final resolution = await PagedWidgetCandidates.resolve(filters: {}, mostRecent: true, database: database);
      expect(resolution.handled, isFalse);
      expect(resolution.entry, isNull);
    });

    test('keeps the legacy path for scopes the SQL layer cannot express', () async {
      await database.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);

      final resolution = await PagedWidgetCandidates.resolve(
        filters: {StoredAlbumFilter('/a', null, reversed: true)},
        mostRecent: true,
        database: database,
      );
      expect(resolution.handled, isFalse);
    });

    test('a paged but empty view is handled with no entry', () async {
      await collectionPagingPrefs.setEngine(CollectionEngine.paged);
      final resolution = await PagedWidgetCandidates.resolve(filters: {}, mostRecent: true, database: database);
      expect(resolution.handled, isTrue);
      expect(resolution.entry, isNull);
    });
  });
}
