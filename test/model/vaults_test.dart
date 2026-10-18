import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:aves/services/storage_service.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../common.dart';
import '../fake/media_fetch_service.dart';
import '../fake/storage_service.dart';
import '../helpers/sqlite3_loader.dart';

/// The vault's recovery flow, which must work whether or not the source holds
/// entries: a windowed source holds none, and would otherwise treat every file
/// in the vault as untracked and re-add it under a fresh id.
void main() {
  late AppDatabase db;
  late DriftLocalMediaDb driftDb;

  setUpAll(() async {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();

    db = AppDatabase(NativeDatabase.memory());
    driftDb = DriftLocalMediaDb(database: db);
    await driftDb.init();
    getIt.unregister<LocalMediaDb>();
    getIt.registerLazySingleton<LocalMediaDb>(() => driftDb);
  });

  tearDownAll(() async {
    await tearDownAllServices();
    await db.close();
  });

  setUp(() async {
    await driftDb.clearEntries();
    await driftDb.clearVaults();
  });

  tearDown(() async {
    await setUpServices();
  });

  AvesEntry entry(int id, String path, {int origin = EntryOrigins.vault}) => AvesEntry(
        id: id,
        uri: Uri.file(path).toString(),
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
        trashed: false,
        origin: origin,
      );

  test('the database, not the source, says which vault files are tracked', () async {
    const details = VaultDetails(name: 'v', autoLockScreenOff: true, useBin: false, lockType: VaultLockType.system);
    await vaults.create(details);
    final vaultDir = details.path;
    try {
      final trackedPath = '$vaultDir/tracked.jpg';
      final untrackedPath = '$vaultDir/untracked.jpg';
      // The tracked file is in the database; the source holds nothing at all.
      await driftDb.insertEntries({entry(1, trackedPath)});

      (getIt<StorageService>() as FakeStorageService).vaultItemPaths = {trackedPath, untrackedPath};
      (getIt<MediaFetchService>() as FakeMediaFetchService).entries = {entry(2, untrackedPath)};

      final recovered = await vaults.recoverUntrackedItems(vaultDir);

      // Recovering the tracked file would re-add it under a fresh id.
      expect(recovered.map((entry) => entry.path), [untrackedPath]);
    } finally {
      await vaults.remove({vaultDir});
    }
  });
}
