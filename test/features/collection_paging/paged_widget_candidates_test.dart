import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/view/paged_widget_candidates.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Home-widget candidates: a paged collection yields a bounded most-recent
/// block instead of a full load; small collections keep the legacy path
/// (null), so the caller falls back unchanged.
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
    test('pages a big library into a bounded most-recent block', () async {
      await database.insertEntries({entry(1, dateTaken: 100), entry(2, dateTaken: 300), entry(3, dateTaken: 200)});
      await collectionPagingPrefs.setLargeThreshold(2);

      final candidates = await PagedWidgetCandidates.load(filters: {}, limit: 2, database: database);
      expect(candidates, isNotNull);
      expect(candidates!.map((e) => e.id), [2, 3]);
    });

    test('catalogs dates onto the candidates', () async {
      await database.insertEntries({entry(1), entry(2)});
      await database.saveCatalogMetadata({CatalogMetadata(id: 1, dateMillis: 999)});
      await collectionPagingPrefs.setLargeThreshold(2);

      final candidates = await PagedWidgetCandidates.load(filters: {}, limit: 10, database: database);
      expect(candidates, isNotNull);
      expect(candidates!.firstWhere((e) => e.id == 1).catalogDateMillis, 999);
    });

    test('keeps the legacy path below the threshold', () async {
      await database.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(100);

      expect(await PagedWidgetCandidates.load(filters: {}, database: database), isNull);
    });

    test('keeps the legacy path for scopes the SQL layer cannot express', () async {
      await database.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);

      final filters = {StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)};
      expect(await PagedWidgetCandidates.load(filters: filters, database: database), isNull);
    });
  });
}
