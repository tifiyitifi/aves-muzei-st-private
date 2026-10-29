import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// The bottom bar's wallpaper entry: the default, the AppMeta round trip and the
/// notification a change sends to every bar already on screen.
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    getIt.registerLazySingleton<AppDatabaseProvider>(() => AppDatabaseProvider(injected: db));
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  test('the default is a separate entry right of the visible range', () async {
    final controller = GroupedWallpaperNavController();
    expect(controller.mode, GroupedWallpaperNavMode.separateRight);
    expect(controller.entryClosed, isFalse);
    expect(controller.derivesEntry, isTrue);

    await controller.load();
    expect(controller.mode, GroupedWallpaperNavMode.separateRight);
    expect(controller.derivesEntry, isTrue);
  });

  test('a mode change is stored and notifies the bars', () async {
    final controller = GroupedWallpaperNavController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setMode(GroupedWallpaperNavMode.shared);

    expect(controller.mode, GroupedWallpaperNavMode.shared);
    expect(controller.derivesEntry, isFalse);
    expect(notifications, 1);
    expect(await WallpaperGroupStore(db).readNavMode(), GroupedWallpaperNavMode.shared);

    final reloaded = GroupedWallpaperNavController();
    await reloaded.load();
    expect(reloaded.mode, GroupedWallpaperNavMode.shared);
  });

  test('closing the entry hides it and survives a reload', () async {
    final controller = GroupedWallpaperNavController();

    await controller.setEntryClosed(true);

    expect(controller.entryClosed, isTrue);
    expect(controller.derivesEntry, isFalse);
    expect(await WallpaperGroupStore(db).readNavEntryClosed(), isTrue);

    final reloaded = GroupedWallpaperNavController();
    await reloaded.load();
    expect(reloaded.entryClosed, isTrue);

    await controller.toggleEntryClosed();
    expect(controller.entryClosed, isFalse);
    expect(controller.derivesEntry, isTrue);
    expect(await WallpaperGroupStore(db).readNavEntryClosed(), isFalse);
  });

  test('an unreadable stored mode falls back to the default', () async {
    await AppMetaStore(db).write({WallpaperGroupStore.keyNavMode: 'from-a-newer-build'});

    expect(await WallpaperGroupStore(db).readNavMode(), defaultGroupedWallpaperNavMode);
  });
}
