import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// The stack index is maintained by the write path: a group's tile is settled
/// over the whole group, so a later write can hand the tile to another row.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    settings.collectionBurstPatterns = [BurstPatterns.samsung];
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
  });

  tearDown(() => db.close());

  AvesEntry entry(int id, {required String path, String mime = MimeTypes.jpeg}) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: path,
        contentId: 100 + id,
        pageId: null,
        sourceMimeType: mime,
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

  Future<Map<int, int?>> tiles() async {
    final rows = await db.customSelect('SELECT id, stackTileId FROM entry ORDER BY id').get();
    return {for (final row in rows) row.data['id'] as int: row.data['stackTileId'] as int?};
  }

  test('inserting a burst frame settles the group tile', () async {
    await service.insertEntries({entry(1, path: '/cam/20151021_072800_002.jpg')});
    // A single frame is its own tile.
    expect(await tiles(), {1: null});

    // The earlier frame takes the tile and the previous one hides behind it.
    await service.insertEntries({entry(2, path: '/cam/20151021_072800_001.jpg')});
    expect(await tiles(), {1: 2, 2: null});
  });

  test('a developed image hides its raw sibling', () async {
    await service.insertEntries({entry(1, path: '/cam/IMG_1.dng', mime: MimeTypes.dng)});
    expect(await tiles(), {1: null});

    await service.insertEntries({entry(2, path: '/cam/IMG_1.jpg')});
    expect(await tiles(), {1: 2, 2: null});
  });

  test('moving the tile out of a group leaves every remaining row visible', () async {
    await service.insertEntries({entry(1, path: '/cam/20151021_072800_001.jpg'), entry(2, path: '/cam/20151021_072800_002.jpg')});
    expect(await tiles(), {1: null, 2: 1});

    // Renaming the tile away hands the group back to the other frame, which now
    // shows itself.
    await service.updateEntry(1, entry(1, path: '/cam/other.jpg'));
    expect(await tiles(), {1: null, 2: null});
  });
}
