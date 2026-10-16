import 'package:aves/features/collection_paging/summary/paged_filter_summaries.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/album_pick_page.dart' as album_pick;
import 'package:aves/widgets/dialogs/pick_dialogs/tag_pick_page.dart' as tag_pick;
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Pick dialogs on huge (paged) libraries must not run a full `init`
/// (materializing everything OOMs). Instead they preload the needed summary
/// domain, and the shared `getGridItems` grids render entry-free.
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

  AvesEntry entry(int id, {String dir = '/album'}) {
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
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 0,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  void attachSummaries() {
    source.summaries = PagedFilterSummaries(
      source: source,
      database: database,
      hiddenFilters: () => {},
      lockedVaultDirs: () => {},
    );
  }

  group('pick preload', () {
    test('album pick preloads summaries without a full load', () async {
      await database.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b')});
      attachSummaries();

      expect(source.targetScope, isNot(CollectionSource.fullScope));
      await album_pick.ensureAlbumPickData(source);

      // no full load happened: source stays entry-free and scopeless
      expect(source.allEntries, isEmpty);
      expect(source.targetScope, isNot(CollectionSource.fullScope));
      expect(source.rawAlbums.toSet(), {'/a', '/b'});
    });

    test('tag pick preloads summaries and grids render entry-free', () async {
      await database.insertEntries({entry(1), entry(2)});
      await database.saveCatalogMetadata({CatalogMetadata(id: 1, xmpSubjects: 'red;blue'), CatalogMetadata(id: 2, xmpSubjects: 'blue')});
      attachSummaries();

      await tag_pick.ensureTagPickData(source);

      expect(source.allEntries, isEmpty);
      expect(source.sortedTags, ['blue', 'red']);
      final items = TagListPage.getGridItems(source, {ChipType.regular}, null);
      expect(items.map((v) => (v.filter as TagFilter).tag).toSet(), {'blue', 'red'});
    });

    test('provider preload methods load their domains', () async {
      await database.insertEntries({entry(1, dir: '/a')});
      await database.saveCatalogMetadata({CatalogMetadata(id: 1, xmpSubjects: 'red')});
      final summaries = PagedFilterSummaries(
        source: source,
        database: database,
        hiddenFilters: () => {},
        lockedVaultDirs: () => {},
      );

      await summaries.ensureAlbums();
      expect(summaries.albumDirectories, ['/a']);

      await summaries.ensureTags();
      expect(summaries.tags, ['red']);

      await summaries.ensureLocations();
      expect(summaries.countries, isEmpty);
    });
  });
}
