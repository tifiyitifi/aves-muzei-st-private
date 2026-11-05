import 'package:aves/features/album_contents_transfer/model/album_rename_visibility.dart';
import 'package:aves/features/album_contents_transfer/services/album_rename_visibility_probe.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// A rename renames the folder, so it moves more than the view shows whenever
/// the album's scope is narrowed. The probe is what tells the two apart.
void main() {
  const albumA = '/storage/emulated/0/Pictures/A';
  const albumB = '/storage/emulated/0/Pictures/B';

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
  });

  tearDownAll(() async {
    await db.close();
    await tearDownAllServices();
  });

  setUp(() async {
    await db.delete(db.entriesTable).go();
    await db.delete(db.metadataTable).go();
    settings.hiddenFilters = const {};
  });

  AvesEntry entry(int id, String directory, {bool trashed = false}) => AvesEntry(
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

  StoredAlbumFilter filter(String album) => StoredAlbumFilter(album, null);

  test('an album whose whole folder is visible may be renamed', () async {
    await service.insertEntries({entry(1, albumA), entry(2, albumA), entry(3, albumB)});

    final visibility = await probeAlbumRenameVisibility(filter(albumA), database: service);

    expect(visibility, isNotNull);
    expect(visibility!.visible, 2);
    expect(visibility.total, 2);
    expect(visibility.coversAlbum, isTrue);
  });

  test('a visible range that leaves rows behind blocks the rename', () async {
    await service.insertEntries({entry(1, albumA), entry(2, albumA), entry(3, albumB)});

    final controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const <VisibleRangePresetDefinition>[]);
    await controller.init();
    VisibleRangeGate.debugController = controller;
    addTearDown(() => VisibleRangeGate.debugController = null);
    await controller.selectBase(presetId: '', name: 'B', filters: {PathFilter(albumB)});

    final visibility = await probeAlbumRenameVisibility(filter(albumA), database: service);

    expect(visibility!.visible, 0);
    expect(visibility.total, 2);
    expect(visibility.unseen, 2);
    expect(visibility.coversAlbum, isFalse);
  });

  test('a hidden filter blocks the rename', () async {
    await service.insertEntries({entry(1, albumA), entry(2, albumA)});
    settings.hiddenFilters = {filter(albumA)};

    final visibility = await probeAlbumRenameVisibility(filter(albumA), database: service);

    expect(visibility!.visible, 0);
    expect(visibility.total, 2);
    expect(visibility.coversAlbum, isFalse);
  });

  test('a trashed row still blocks the rename', () async {
    await service.insertEntries({entry(1, albumA), entry(2, albumA, trashed: true)});

    final visibility = await probeAlbumRenameVisibility(filter(albumA), database: service);

    expect(visibility!.visible, 1);
    expect(visibility.total, 2);
    expect(visibility.unseen, 1);
  });

  test('an empty album is covered, not blocked', () async {
    final visibility = await probeAlbumRenameVisibility(filter(albumA), database: service);

    expect(visibility!.visible, 0);
    expect(visibility.total, 0);
    expect(visibility.coversAlbum, isTrue);
  });

  test('a database behind the view never reports unseen rows', () {
    // The scan can insert rows before the database has them: the view then
    // shows more than the folder count, which must not block a rename.
    const visibility = AlbumRenameVisibility(visible: 3, total: 1);

    expect(visibility.unseen, 0);
    expect(visibility.coversAlbum, isTrue);
  });
}
