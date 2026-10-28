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

/// `SavedGroupedWallpaperPlanStore`: the wallpaper follows the committed group,
/// never the page's draft, and remembers an explicit off switch.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupStore groups;
  late VisibleRangeStore ranges;
  late SavedGroupedWallpaperPlanStore planStore;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    groups = WallpaperGroupStore(db);
    ranges = VisibleRangeStore(db);
    planStore = SavedGroupedWallpaperPlanStore(provider: AppDatabaseProvider(injected: db));
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

    final plan = await planStore.load();

    expect(plan.group.id, 'b');
    expect(plan.group.number, 2);
    expect(plan.range?.baseFilters, {PathFilter('/dcim')});
    expect(plan.locked, isFalse);
    expect(plan.isNone, isFalse);
  });

  test('falls back to group 0 when no group is current', () async {
    await groups.saveGroups([group('a'), group('b')]);
    await ranges.saveRange(range('a', base: {PathFilter('/dcim')}));

    final plan = await planStore.load();

    expect(plan.group.isNone, isTrue);
    expect(plan.group.number, 0);
    expect(plan.range, isNull);
  });

  test('a disabled current group falls back to group 0', () async {
    await groups.saveGroups([group('a', enabled: false, current: true), group('b')]);

    expect((await planStore.load()).group.isNone, isTrue);
  });

  test('a missing range is an unrestricted group, not a failure', () async {
    await groups.saveGroups([group('a', current: true)]);

    final plan = await planStore.load();

    expect(plan.group.id, 'a');
    expect(plan.range, isNull);
    expect(plan.locked, isFalse);
  });

  test('a locked range is reported as locked', () async {
    await groups.saveGroups([group('a', current: true)]);
    await ranges.saveRange(range('a', locked: true));

    expect((await planStore.load()).locked, isTrue);
  });

  test('the page draft does not change what the wallpaper uses', () async {
    await groups.saveGroups([group('a', current: true), group('b')]);
    final controller = WallpaperGroupController(injectedDatabase: db, defaultLoader: () async => []);
    await controller.init();
    await controller.beginDraft();
    await controller.selectCurrent('b');
    expect(controller.current.id, 'b');
    expect(controller.dirty, isTrue);

    final plan = await planStore.load();

    expect(plan.group.id, 'a');
  });

  test('an install that was never switched off is enabled', () async {
    await groups.saveGroups([group('a', current: true)]);

    final plan = await planStore.load();

    expect(plan.disabled, isFalse);
    expect(plan.enabled, isTrue);
  });

  test('the off switch survives a reload without touching the current group', () async {
    await groups.saveGroups([group('a', current: true), group('b')]);

    await planStore.setDisabled(true);
    final off = await planStore.load();
    expect(off.disabled, isTrue);
    expect(off.enabled, isFalse);
    // Turning the feature off keeps the group, so turning it back on returns to
    // the same content instead of guessing.
    expect(off.group.id, 'a');

    await planStore.setDisabled(false);
    expect((await planStore.load()).disabled, isFalse);
  });

  test('adopting the first enabled group makes it current and turns the feature on', () async {
    await groups.saveGroups([group('a', enabled: false), group('b'), group('c')]);
    await planStore.setDisabled(true);

    final plan = await planStore.adoptFirstEnabledGroup();

    expect(plan.group.id, 'b');
    expect(plan.group.current, isTrue);
    expect(plan.disabled, isFalse);
    expect((await planStore.load()).group.id, 'b');
    expect((await planStore.load()).disabled, isFalse);
  });

  test('adopting keeps the group that is already current', () async {
    await groups.saveGroups([group('a'), group('b', current: true)]);

    final plan = await planStore.adoptFirstEnabledGroup();

    expect(plan.group.id, 'b');
    expect(plan.group.number, 2);
  });

  test('adopting with no enabled group leaves the feature off', () async {
    await groups.saveGroups([group('a', enabled: false), group('b', enabled: false)]);

    final plan = await planStore.adoptFirstEnabledGroup();

    expect(plan.isNone, isTrue);
    expect(plan.disabled, isTrue);
    expect((await planStore.load()).disabled, isTrue);
  });

  test('the adopted plan carries the group range', () async {
    await groups.saveGroups([group('a')]);
    await ranges.saveRange(range('a', base: {PathFilter('/dcim')}));

    final plan = await planStore.adoptFirstEnabledGroup();

    expect(plan.range?.baseFilters, {PathFilter('/dcim')});
  });

  test('paused survives a reload without touching the current group', () async {
    await groups.saveGroups([group('a', current: true)]);
    expect((await planStore.load()).paused, isFalse);

    await planStore.setPaused(true);

    final paused = await planStore.load();
    expect(paused.paused, isTrue);
    expect(paused.group.id, 'a');
  });

  test('activation resumes a frozen wallpaper', () async {
    await groups.saveGroups([group('a', current: true)]);
    await planStore.setPaused(true);

    final plan = await planStore.adoptFirstEnabledGroup();

    expect(plan.paused, isFalse);
    expect((await planStore.load()).paused, isFalse);
  });

  test('next group skips disabled groups and wraps around', () async {
    await groups.saveGroups([group('a', current: true), group('b', enabled: false), group('c')]);

    final next = await planStore.switchGroup(1);
    expect(next.group.id, 'c');
    expect((await planStore.load()).group.id, 'c');

    final wrapped = await planStore.switchGroup(1);
    expect(wrapped.group.id, 'a');
  });

  test('previous group wraps to the last enabled group', () async {
    await groups.saveGroups([group('a', current: true), group('b', enabled: false), group('c')]);

    final previous = await planStore.switchGroup(-1);

    expect(previous.group.id, 'c');
  });

  test('from group 0 next enters at the first enabled and previous at the last', () async {
    await groups.saveGroups([group('a'), group('b', enabled: false), group('c')]);
    expect((await planStore.switchGroup(1)).group.id, 'a');

    await groups.saveGroups([group('a'), group('b', enabled: false), group('c')]);
    expect((await planStore.switchGroup(-1)).group.id, 'c');
  });

  test('switching group resumes a frozen wallpaper', () async {
    await groups.saveGroups([group('a', current: true), group('b')]);
    await planStore.setPaused(true);

    final plan = await planStore.switchGroup(1);

    expect(plan.group.id, 'b');
    expect(plan.paused, isFalse);
    expect((await planStore.load()).paused, isFalse);
  });

  test('switching with no enabled group keeps group 0', () async {
    await groups.saveGroups([group('a', enabled: false), group('b', enabled: false)]);

    final plan = await planStore.switchGroup(1);

    expect(plan.isNone, isTrue);
  });
}
