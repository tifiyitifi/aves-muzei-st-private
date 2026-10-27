import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_plan.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// `SavedGroupedWallpaperPlanLoader`: the wallpaper follows the committed group,
/// never the page's draft.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupStore groups;
  late VisibleRangeStore ranges;
  late SavedGroupedWallpaperPlanLoader loader;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    groups = WallpaperGroupStore(db);
    ranges = VisibleRangeStore(db);
    loader = SavedGroupedWallpaperPlanLoader(provider: AppDatabaseProvider(injected: db));
  });

  tearDown(() => db.close());

  WallpaperGroup group(String id, {bool enabled = true, bool current = false}) =>
      WallpaperGroup(id: id, name: '@wallpaperGroupDefaultAll', enabled: enabled, current: current, createdAt: 1, updatedAt: 2);

  VisibleRange range(String groupId, {bool locked = false, Set<CollectionFilter> base = const {}}) => VisibleRange(
        id: wallpaperGroupRangeId(groupId),
        scope: VisibleRangeScope.wallpaper,
        ownerId: groupId,
        baseName: '@wallpaperGroupDefaultDcim',
        baseFilters: base,
        locked: locked,
        createdAt: 1,
        updatedAt: 2,
      );

  test('loads the current enabled group and its saved range', () async {
    await groups.saveGroups([group('a'), group('b', current: true)]);
    await ranges.saveRange(range('b', base: {PathFilter('/dcim')}));

    final plan = await loader.load();

    expect(plan.group.id, 'b');
    expect(plan.group.number, 2);
    expect(plan.range?.baseFilters, {PathFilter('/dcim')});
    expect(plan.locked, isFalse);
    expect(plan.isNone, isFalse);
  });

  test('falls back to group 0 when no group is current', () async {
    await groups.saveGroups([group('a'), group('b')]);
    await ranges.saveRange(range('a', base: {PathFilter('/dcim')}));

    final plan = await loader.load();

    expect(plan.group.isNone, isTrue);
    expect(plan.group.number, 0);
    expect(plan.range, isNull);
  });

  test('a disabled current group falls back to group 0', () async {
    await groups.saveGroups([group('a', enabled: false, current: true), group('b')]);

    expect((await loader.load()).group.isNone, isTrue);
  });

  test('a missing range is an unrestricted group, not a failure', () async {
    await groups.saveGroups([group('a', current: true)]);

    final plan = await loader.load();

    expect(plan.group.id, 'a');
    expect(plan.range, isNull);
    expect(plan.locked, isFalse);
  });

  test('a locked range is reported as locked', () async {
    await groups.saveGroups([group('a', current: true)]);
    await ranges.saveRange(range('a', locked: true));

    expect((await loader.load()).locked, isTrue);
  });

  test('the page draft does not change what the wallpaper uses', () async {
    await groups.saveGroups([group('a', current: true), group('b')]);
    final controller = WallpaperGroupController(injectedDatabase: db, defaultLoader: () async => []);
    await controller.init();
    await controller.beginDraft();
    await controller.selectCurrent('b');
    expect(controller.current.id, 'b');
    expect(controller.dirty, isTrue);

    final plan = await loader.load();

    expect(plan.group.id, 'a');
  });
}
