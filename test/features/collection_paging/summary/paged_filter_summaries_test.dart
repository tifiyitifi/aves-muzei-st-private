import 'package:aves/features/collection_paging/summary/paged_filter_summaries.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/container/tag_group.dart';
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

  /// Waits for a lazily-kicked summary computation to land.
  Future<void> settle(bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('summary did not settle');
  }

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
      expect(s.mimeTypes, isEmpty);
      expect(s.albumCount(StoredAlbumFilter('/a', null)), 0);
      expect(s.albumRecentEntry(StoredAlbumFilter('/a', null)), isNull);
      expect(s.tagCount(TagFilter('x')), 0);
    });

    test('the formats load lazily from the database', () async {
      await database.insertEntries({entry(1), entry(2, sourceDateTaken: 100)});
      await database.saveCatalogMetadata({CatalogMetadata(id: 2, mimeType: 'image/heic')});
      final s = summaries();

      // Empty until touched, then served from the database: the search page has
      // no entries to scan on a windowed library.
      expect(s.mimeTypes, isEmpty);
      await settle(() => s.mimeTypes.isNotEmpty);
      expect(s.mimeTypes, ['image/heic', 'image/jpeg']);
    });

    test('ensureMimes preloads the formats', () async {
      await database.insertEntries({entry(1)});
      final s = summaries();
      await s.ensureMimes();
      expect(s.mimeTypes, ['image/jpeg']);
    });

    test('album media kinds come from the rows, unioned over a group', () async {
      await database.insertEntries({entry(1, dir: '/images'), entry(2, dir: '/videos')});
      await database.saveCatalogMetadata({CatalogMetadata(id: 2, mimeType: 'video/mp4')});
      final s = summaries();
      await s.ensureLoaded(SummaryDomain.albums);

      expect(s.albumMediaKinds(StoredAlbumFilter('/images', null)), (hasImage: true, hasVideo: false));
      expect(s.albumMediaKinds(StoredAlbumFilter('/videos', null)), (hasImage: false, hasVideo: true));
      // A group holds what its members hold, like the legacy scan of its entries.
      final group = AlbumGroupFilter(
        Uri.parse('/group'),
        SetOrFilter({StoredAlbumFilter('/images', null), StoredAlbumFilter('/videos', null)}),
      );
      expect(s.albumMediaKinds(group), (hasImage: true, hasVideo: true));
    });

    test('resolves an album group aggregate on first touch', () async {
      await database.insertEntries({
        entry(1, dir: '/a', size: 10, sourceDateTaken: 100),
        entry(2, dir: '/b', size: 20, sourceDateTaken: 300),
        entry(3, dir: '/c', size: 30, sourceDateTaken: 200),
      });
      final s = summaries();
      await s.ensureLoaded(SummaryDomain.albums);

      final group = AlbumGroupFilter(
        Uri.parse('/group'),
        SetOrFilter({StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)}),
      );
      // unknown on first touch, then resolved from the database and cached
      expect(s.albumCount(group), 0);
      await settle(() => s.albumCount(group) > 0);
      expect(s.albumCount(group), 2);
      expect(s.albumSize(group), 30);
      expect(s.albumMaxBestDate(group), 300);
      expect(s.albumRecentEntry(group)?.id, 2);
    });

    test('a tag group counts an entry once when several members match', () async {
      await database.insertEntries({entry(1, sourceDateTaken: 100), entry(2, sourceDateTaken: 300)});
      await database.saveCatalogMetadata({CatalogMetadata(id: 1, xmpSubjects: 'red;blue'), CatalogMetadata(id: 2, xmpSubjects: 'blue')});
      final s = summaries();
      await s.ensureLoaded(SummaryDomain.tags);

      final group = TagGroupFilter(Uri.parse('/taggroup'), SetOrFilter({TagFilter('red'), TagFilter('blue')}));
      await settle(() => s.tagCount(group) > 0);
      // entry 1 carries both member tags: the union is {1, 2}, not the sum (3)
      expect(s.tagCount(group), 2);
      expect(s.tagRecentEntry(group)?.id, 2);
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

    test('loads tag and location summaries', () async {      await database.insertEntries({entry(1, sourceDateTaken: 100), entry(2, sourceDateTaken: 300)});
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
