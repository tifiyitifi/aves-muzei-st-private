import 'package:aves/features/collection_paging/summary/paged_filter_summaries.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';
import '../../../helpers/sqlite3_loader.dart';

/// Paged filter summaries: lazy per-domain loading, sync cache reads, and
/// `CollectionSource` delegation for entry-free sources, against an in-memory
/// Drift database.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  late AppDatabase db;
  late DriftLocalMediaDb database;
  late MediaStoreSource source;

  setUp(() async {
    await setUpServices();
    db = AppDatabase(NativeDatabase.memory());
    database = DriftLocalMediaDb(database: db);
    await database.init();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    await setUpServices();
    await db.close();
  });

  AvesEntry entry(
    int id, {
    String dir = '/album',
    int size = 5,
    int sourceDateTaken = 0,
  }) {
    return AvesEntry(
      id: id,
      uri: 'content://media/external/images/media/${100 + id}',
      path: '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: size,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: sourceDateTaken,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  PagedFilterSummaries summaries() => PagedFilterSummaries(
        source: source,
        database: database,
        hiddenFilters: () => {},
        lockedVaultDirs: () => {},
      );

  group('PagedFilterSummaries', () {
    test('sync getters are empty before loading', () {
      final s = summaries();
      expect(s.albumDirectories, isEmpty);
      expect(s.tags, isEmpty);
      expect(s.albumCount(StoredAlbumFilter('/a', null)), 0);
      expect(s.albumRecentEntry(StoredAlbumFilter('/a', null)), isNull);
      expect(s.tagCount(TagFilter('x')), 0);
    });

    test('loads album summaries with covers on demand', () async {
      await database.insertEntries({entry(1, dir: '/a', size: 10, sourceDateTaken: 100), entry(2, dir: '/a', size: 20, sourceDateTaken: 300)});
      final s = summaries();
      await s.ensureLoaded(SummaryDomain.albums);

      expect(s.albumDirectories, ['/a']);
      final filter = StoredAlbumFilter('/a', null);
      expect(s.albumCount(filter), 2);
      expect(s.albumSize(filter), 30);
      expect(s.albumMaxBestDate(filter), 300);
      expect(s.albumRecentEntry(filter)?.id, 2);
      // cover falls back to the recent entry without a user-set cover
      expect(s.coverEntry(filter)?.id, 2);
    });

    test('loads tag and location summaries', () async {
      await database.insertEntries({entry(1, sourceDateTaken: 100), entry(2, sourceDateTaken: 300)});
      await database.saveCatalogMetadata({CatalogMetadata(id: 1, xmpSubjects: 'red;blue'), CatalogMetadata(id: 2, xmpSubjects: 'blue')});
      final s = summaries();
      await s.ensureLoaded(SummaryDomain.tags);

      expect(s.tags, ['blue', 'red']);
      expect(s.tagCount(TagFilter('blue')), 2);
      expect(s.tagRecentEntry(TagFilter('blue'))?.id, 2);
      expect(s.tagRecentEntry(TagFilter('nope')), isNull);
    });

    test('second load is a no-op without invalidation', () async {
      await database.insertEntries({entry(1, dir: '/a')});
      final s = summaries();
      await s.ensureLoaded(SummaryDomain.albums);
      expect(s.albumDirectories, ['/a']);

      await database.insertEntries({entry(2, dir: '/b')});
      await s.ensureLoaded(SummaryDomain.albums);
      expect(s.albumDirectories, ['/a']);

      s.invalidate();
      await s.ensureLoaded(SummaryDomain.albums);
      expect(s.albumDirectories, ['/a', '/b']);
    });
  });

  group('CollectionSource delegation', () {
    test('entry-free source serves provider values', () async {
      await database.insertEntries({entry(1, dir: '/a', size: 10, sourceDateTaken: 100)});
      source.summaries = summaries();
      await (source.summaries as PagedFilterSummaries).ensureLoaded(SummaryDomain.albums);

      expect(source.allEntries, isEmpty);
      expect(source.rawAlbums, ['/a']);
      final filter = StoredAlbumFilter('/a', null);
      expect(source.count(filter), 1);
      expect(source.size(filter), 10);
      expect(source.recentEntry(filter)?.id, 1);
      expect(source.coverEntry(filter)?.id, 1);
      expect(source.sortedTags, isEmpty);
    });

    test('source without provider keeps legacy behaviour', () {
      expect(source.summaries, isNull);
      expect(source.rawAlbums, isEmpty);
      expect(source.count(StoredAlbumFilter('/a', null)), 0);
      expect(source.recentEntry(TagFilter('x')), isNull);
      expect(source.coverEntry(LocationFilter(LocationLevel.country, 'France;FR')), isNull);
    });
  });
}
