import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// A whole-folder rename moves the files with a native call and then carries
/// the rows over: ids stay (favourites, covers, pins and bookmarks point at
/// them), and only the derived location columns follow.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUp(() async {
    settings.collectionBurstPatterns = [BurstPatterns.samsung];
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
  });

  tearDown(() => db.close());

  AvesEntry entry(
    int id, {
    required String path,
    String? uri,
    int origin = EntryOrigins.mediaStoreContent,
    bool trashed = false,
  }) =>
      AvesEntry(
        id: id,
        uri: uri ?? 'content://media/external/images/media/$id',
        path: path,
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
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: trashed,
        origin: origin,
      );

  Future<Map<String, Object?>> row(int id) async {
    final rows = await db.customSelect('SELECT * FROM entry WHERE id = ?', variables: [Variable(id)]).get();
    return rows.single.data;
  }

  test('moves the folder rows, keeps their identity, and leaves siblings alone', () async {
    await service.insertEntries({
      entry(1, path: '/storage/emulated/0/Pictures/holidays/a.jpg'),
      entry(2, path: '/storage/emulated/0/Pictures/holidays/sub/b.jpg'),
      // shares the prefix but is another folder
      entry(3, path: '/storage/emulated/0/Pictures/holidays2/c.jpg'),
      // differs only in case
      entry(4, path: '/storage/emulated/0/Pictures/Holidays/d.jpg'),
      entry(5, path: '/storage/emulated/0/Pictures/other/e.jpg'),
    });

    final moved = await service.renameDirectoryPrefix(
      oldDirectory: '/storage/emulated/0/Pictures/holidays',
      newDirectory: '/storage/emulated/0/Pictures/Trips',
    );
    expect(moved, 2);

    final direct = await row(1);
    expect(direct['path'], '/storage/emulated/0/Pictures/Trips/a.jpg');
    expect(direct['directory'], '/storage/emulated/0/Pictures/Trips');
    // identity, not location
    expect(direct['id'], 1);
    expect(direct['contentId'], 101);
    expect(direct['uri'], 'content://media/external/images/media/1');

    // a subfolder travels with the folder it sits in
    final nested = await row(2);
    expect(nested['path'], '/storage/emulated/0/Pictures/Trips/sub/b.jpg');
    expect(nested['directory'], '/storage/emulated/0/Pictures/Trips/sub');

    expect((await row(3))['path'], '/storage/emulated/0/Pictures/holidays2/c.jpg');
    expect((await row(4))['path'], '/storage/emulated/0/Pictures/Holidays/d.jpg');
    expect((await row(5))['path'], '/storage/emulated/0/Pictures/other/e.jpg');
  });

  test('rewrites a file uri, which is a path, and only for the vault rows that hold one', () async {
    // A space reaches the database encoded in the uri, as the platform builds
    // it with `Uri.fromFile`.
    const oldDir = '/data/user/0/deckers.thibault.aves/files/vault/Old Album';
    const newDir = '/data/user/0/deckers.thibault.aves/files/vault/New Album';
    await service.insertEntries({
      entry(
        1,
        path: '$oldDir/a.jpg',
        uri: 'file:///data/user/0/deckers.thibault.aves/files/vault/Old%20Album/a.jpg',
        origin: EntryOrigins.vault,
      ),
      entry(2, path: '$oldDir/b.jpg'),
    });

    await service.renameDirectoryPrefix(oldDirectory: oldDir, newDirectory: newDir);

    expect((await row(1))['uri'], 'file:///data/user/0/deckers.thibault.aves/files/vault/New%20Album/a.jpg');
    expect((await row(2))['uri'], 'content://media/external/images/media/2');
  });

  test('moves a burst group together, keeping its key shape and its tile', () async {
    await service.insertEntries({
      entry(1, path: '/cam/20151021_072800_001.jpg'),
      entry(2, path: '/cam/20151021_072800_002.jpg'),
    });
    final tileBefore = (await row(2))['stackTileId'];
    expect(tileBefore, 1);

    await service.renameDirectoryPrefix(oldDirectory: '/cam', newDirectory: '/trips');

    expect((await row(1))['stackKey'], '/trips/20151021_072800');
    expect((await row(2))['stackKey'], '/trips/20151021_072800');
    // which member shows is a property of the group, not of its path
    expect((await row(2))['stackTileId'], 1);
  });

  test('a second run matches nothing', () async {
    await service.insertEntries({entry(1, path: '/cam/a.jpg')});

    final first = await service.renameDirectoryPrefix(oldDirectory: '/cam', newDirectory: '/trips');
    final second = await service.renameDirectoryPrefix(oldDirectory: '/cam', newDirectory: '/trips');

    expect(first, 1);
    expect(second, 0);
    expect((await row(1))['path'], '/trips/a.jpg');
  });

  test('countInDirectory counts what the folder holds, not what a view shows', () async {
    await service.insertEntries({
      entry(1, path: '/cam/a.jpg'),
      // hidden by any view that excludes the trash, yet inside the folder
      entry(2, path: '/cam/b.jpg', trashed: true),
      entry(3, path: '/cam/sub/c.jpg'),
      entry(4, path: '/cam2/d.jpg'),
    });

    expect(await service.countInDirectory('/cam'), 2);
    expect(await service.countInDirectory('/cam/sub'), 1);
    expect(await service.countInDirectory('/missing'), 0);
  });
}
