import 'package:aves/features/album_contents_transfer/services/album_contents_entry_feed.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// The album action's feed: bounded, id-ordered batches of exactly the selected
/// albums' rows, frozen at the count it was built with.
void main() {
  const albumA = '/storage/emulated/0/Pictures/A';
  const albumB = '/storage/emulated/0/Pictures/B';
  const albumC = '/storage/emulated/0/Pictures/C';

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    // The feed's metadata attach reads the app-wide database, which the app
    // resolves once per isolate: one connection for the whole file, cleared
    // between tests.
    getIt.unregister<LocalMediaDb>();
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
    getIt.registerLazySingleton<LocalMediaDb>(() => service);
  });

  tearDownAll(() async {
    await db.close();
    await tearDownAllServices();
  });

  setUp(() async {
    await db.delete(db.entriesTable).go();
    await db.delete(db.metadataTable).go();
    await db.delete(db.addressesTable).go();
  });

  AvesEntry entry(int id, String directory, {bool trashed = false}) {
    return AvesEntry(
      id: id,
      uri: 'content://$directory/$id',
      path: '$directory/$id.jpg',
      contentId: id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: '$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  StoredAlbumFilter filter(String album) => StoredAlbumFilter(album, null);

  CollectionWindowPredicate unionPredicate(Set<String> albums) {
    final filters = albums.map(filter).toSet();
    return predicateForFilters(filters.length > 1 ? {SetOrFilter(filters.toSet())} : filters)!;
  }

  Future<AlbumContentsEntryFeed> feed(Set<String> albums, {int? frozenCount}) async {
    final filters = albums.map(filter).toSet();
    final predicate = unionPredicate(albums);
    final count = frozenCount ?? await service.countEntries(predicate);
    return AlbumContentsEntryFeed(albums: filters, predicate: predicate, count: count);
  }

  List<int> idsOf(List<AvesEntry> entries) => [for (final entry in entries) entry.id]..sort();

  test('walks every row of the scope once, in bounded batches', () async {
    await service.insertEntries({
      for (var i = 1; i <= 200; i++) entry(i, albumA),
      for (var i = 201; i <= 400; i++) entry(i, albumB),
      entry(999, albumC),
    });

    final sut = await feed({albumA, albumB});

    final batches = await sut.batches().toList();
    final walked = [for (final batch in batches) ...batch];

    expect(sut.count, 400);
    expect(batches, isNotEmpty);
    expect(batches.every((batch) => batch.length <= entryFeedBatchSize), isTrue);
    expect(walked, hasLength(400));
    expect(walked.map((entry) => entry.id).toSet(), {for (var i = 1; i <= 400; i++) i});
    // An album outside the scope never rides along.
    expect(walked.any((entry) => entry.id == 999), isFalse);
    expect(walked.every((entry) => entry.directory == albumA || entry.directory == albumB), isTrue);
  });

  test('walks the rows in id order', () async {
    await service.insertEntries({entry(3, albumA), entry(1, albumA), entry(2, albumB)});

    final sut = await feed({albumA, albumB});

    final walked = [for (final batch in (await sut.batches().toList())) ...batch];
    expect(walked.map((entry) => entry.id), [1, 2, 3]);
  });

  test('stops at the count it was frozen with', () async {
    await service.insertEntries({for (var i = 1; i <= 10; i++) entry(i, albumA)});

    final sut = await feed({albumA}, frozenCount: 4);

    final walked = [for (final batch in (await sut.batches().toList())) ...batch];
    expect(idsOf(walked), [1, 2, 3, 4]);
  });

  test('reports the first entry of an empty scope as null', () async {
    await service.insertEntries({entry(1, albumA)});

    final sut = await feed({albumB});

    expect(sut.count, 0);
    expect(await sut.first(), isNull);
    expect(await sut.batches().toList(), isEmpty);
  });

  test('refuses to materialize a scope past the shared limit', () async {
    await service.insertEntries({for (var i = 1; i <= 5; i++) entry(i, albumA)});

    final sut = await feed({albumA});

    expect(
      () => sut.materialize(limit: 4),
      throwsA(isA<EntryFeedTooLargeException>()),
    );
  });
}
