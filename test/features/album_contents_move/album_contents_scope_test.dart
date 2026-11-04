import 'package:aves/features/album_contents_move/services/album_contents_scope.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// The database scope of an album selection: per-album counts, the union total,
/// and the live-only rule the in-memory source also applies.
void main() {
  const albumA = '/storage/emulated/0/Pictures/A';
  const albumB = '/storage/emulated/0/Pictures/B';
  const albumC = '/storage/emulated/0/Pictures/C';

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    // The scope probes the app-wide database, which the app resolves once per
    // isolate: one connection for the whole file, cleared between tests.
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

  test('counts each selected album and their union', () async {
    await service.insertEntries({
      entry(1, albumA),
      entry(2, albumA),
      entry(3, albumB),
      entry(4, albumC),
    });

    final scope = await AlbumContentsScope.resolve({filter(albumA), filter(albumB)}, database: service);

    expect(scope, isNotNull);
    expect(scope!.countByAlbum, {albumA: 2, albumB: 1});
    expect(scope.entryCount, 3);
    expect(scope.countIn(albumA), 2);
    // An unselected album is not part of the scope.
    expect(scope.countIn(albumC), 0);
  });

  test('resolves a single album', () async {
    await service.insertEntries({entry(1, albumA), entry(2, albumB)});

    final scope = await AlbumContentsScope.resolve({filter(albumA)}, database: service);

    expect(scope!.countByAlbum, {albumA: 1});
    expect(scope.countIn(albumB), 0);
  });

  test('counts live entries only', () async {
    await service.insertEntries({entry(1, albumA), entry(2, albumA, trashed: true)});

    final scope = await AlbumContentsScope.resolve({filter(albumA)}, database: service);

    expect(scope!.entryCount, 1);
  });

  test('keeps a selected album with no entries in the scope', () async {
    await service.insertEntries({entry(1, albumA)});

    final scope = await AlbumContentsScope.resolve({filter(albumA), filter(albumB)}, database: service);

    expect(scope!.countByAlbum, {albumA: 1, albumB: 0});
    expect(scope.entryCount, 1);
  });

  test('compiles the union of several albums', () {
    final predicate = AlbumContentsScope.predicateFor({filter(albumA), filter(albumB)});

    expect(predicate, isNotNull);
  });

  test('answers null for an empty selection', () async {
    expect(AlbumContentsScope.predicateFor(const {}), isNull);
    expect(await AlbumContentsScope.resolve(const {}, database: service), isNull);
  });
}
