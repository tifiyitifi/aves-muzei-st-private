import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/search_filters/model/range_assist_filter.dart';
import 'package:aves/features/search_filters/services/assist_counter.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// The sheet's match count must describe the rows the grid would show: the same
/// visible range, hidden filters, locked vaults and stack filter.
void main() {
  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    // One connection for the file: `localMediaDb` is a top-level final resolved
    // on first use, so the fixture and the counter must share it.
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
    getIt.unregister<LocalMediaDb>();
    getIt.registerSingleton<LocalMediaDb>(service);
    await vaults.init();
  });

  tearDownAll(() async {
    vaults.dispose();
    await db.close();
    await tearDownAllServices();
  });

  setUp(() async {
    await setUpServices();
    settings.collectionBurstPatterns = [BurstPatterns.samsung];
    await db.delete(db.entriesTable).go();
    await db.delete(db.vaultsTable).go();
    // The vault list caches the rows it read at `init`.
    await vaults.init();
  });

  AvesEntry entry(int id, {required String path, int sizeBytes = 10}) => AvesEntry(
    id: id,
    uri: 'content://$id',
    path: path,
    contentId: 100 + id,
    pageId: null,
    sourceMimeType: MimeTypes.jpeg,
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: sizeBytes,
    sourceTitle: 'title$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 0,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  test('an empty condition reports no count', () async {
    expect(await AssistCounter.count({}), isNull);
  });

  test('a condition with no SQL translation reports no count', () async {
    expect(await AssistCounter.count({QueryFilter('/regex/', ACalendar.gregorian)}), isNull);
  });

  test('the count covers the rows the condition matches', () async {
    await service.insertEntries({
      entry(1, path: '/a/1.jpg', sizeBytes: 10),
      entry(2, path: '/a/2.jpg', sizeBytes: 2000),
      entry(3, path: '/a/3.jpg', sizeBytes: 3000),
    });

    expect(await AssistCounter.count({RangeAssistFilter(AssistRangeField.size, min: 2000)}), 2);
  });

  test('a hidden album is not counted', () async {
    await service.insertEntries({
      entry(1, path: '/a/1.jpg'),
      entry(2, path: '/b/2.jpg'),
    });

    settings.hiddenFilters = {StoredAlbumFilter('/a', null)};

    expect(await AssistCounter.count({MimeFilter.image}), 1);
  });

  test('a stack member does not count twice', () async {
    // The second frame hides behind the first, so the grid shows one tile.
    await service.insertEntries({
      entry(1, path: '/cam/20151021_072800_001.jpg'),
      entry(2, path: '/cam/20151021_072800_002.jpg'),
    });

    expect(await AssistCounter.count({MimeFilter.image}), 1);
  });

  test('a database that cannot open reports no count', () async {
    // A closed connection stands for a store that is not ready; the sheet must
    // omit the number instead of surfacing the failure.
    final closed = AppDatabase(NativeDatabase.memory());
    await closed.customSelect('SELECT 1').get();
    await closed.close();
    final closedService = DriftLocalMediaDb(database: closed);

    expect(await AssistCounter.count({MimeFilter.image}, database: closedService), isNull);
  });

  test('a locked vault is not counted', () async {
    const details = VaultDetails(name: 'private', autoLockScreenOff: false, useBin: false, lockType: VaultLockType.system);
    await vaults.create(details);
    vaults.lock({details.path});
    await service.insertEntries({
      entry(1, path: '${details.path}/a.jpg'),
      entry(2, path: '/b/b.jpg'),
    });

    expect(await AssistCounter.count({MimeFilter.image}), 1);
  });
}
