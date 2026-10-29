import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_usage.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Persistence of the group list and the cascade onto each group's range.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = WallpaperGroupStore(db);
  });

  tearDown(() => db.close());

  WallpaperGroup group(String id, {bool enabled = true, bool current = false, String name = ''}) =>
      WallpaperGroup(id: id, name: name, enabled: enabled, current: current, createdAt: 1, updatedAt: 2);

  test('round-trips the list in display order with derived numbers', () async {
    await store.saveGroups([
      group('a'),
      group('b', current: true),
      group('c', enabled: false),
    ]);

    final loaded = await store.loadGroups();
    expect(loaded.map((g) => g.id), ['a', 'b', 'c']);
    expect(loaded.map((g) => g.number), [1, 2, 3]);
    expect(loaded.map((g) => g.current), [false, true, false]);
    expect(loaded.last.enabled, isFalse);
    expect(loaded.first.createdAt, 1);
    expect(loaded.first.updatedAt, 2);
  });

  test('saving the whole list rewrites the stored order', () async {
    await store.saveGroups([group('a'), group('b'), group('c')]);
    await store.saveGroups([group('c'), group('a'), group('b')]);

    expect((await store.loadGroups()).map((g) => g.id), ['c', 'a', 'b']);
  });

  test('a group keeps its own interval and ordering', () async {
    await store.saveGroups([
      group('a').copyWith(interval: WallpaperInterval.h1, ordering: GroupedWallpaperOrdering.random),
      group('b'),
    ]);

    var loaded = await store.loadGroups();
    expect(loaded.first.interval, WallpaperInterval.h1);
    expect(loaded.first.ordering, GroupedWallpaperOrdering.random);
    expect(loaded.last.interval, WallpaperInterval.never);
    expect(loaded.last.ordering, GroupedWallpaperOrdering.newThenRandom);

    await store.writeAutoAdvance('a', interval: WallpaperInterval.m15);

    loaded = await store.loadGroups();
    expect(loaded.first.interval, WallpaperInterval.m15);
    expect(loaded.first.ordering, GroupedWallpaperOrdering.random);
    // The contract only affects future picks, so it must not re-bake the frame.
    expect(loaded.first.updatedAt, 2);
  });

  test('deleting a group also deletes its range, rules and applied targets', () async {
    await store.saveGroups([group('a'), group('b')]);
    final ranges = VisibleRangeStore(db);
    final rangeId = wallpaperGroupRangeId('b');
    await ranges.saveRange(
      VisibleRange(
        id: rangeId,
        scope: VisibleRangeScope.wallpaper,
        ownerId: 'b',
        baseFilters: {PathFilter('/pictures')},
        rules: [
          VisibleRangeRule(id: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, filters: {MimeFilter.image}),
        ],
        createdAt: 1,
        updatedAt: 2,
      ),
    );
    await ranges.saveUsage(VisibleRangeRuleUsage.forRule(ruleId: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, usedAt: 1));
    expect(await ranges.loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'b'), isNotNull);

    await store.deleteGroup('b');

    expect((await store.loadGroups()).map((g) => g.id), ['a']);
    expect(await ranges.loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'b'), isNull);
    expect(await db.select(db.visibleRangeRuleRows).get(), isEmpty);
    expect(await db.select(db.visibleRangeRuleUsageRows).get(), isEmpty);
  });

  test('the defaults version round-trips through appMeta', () async {
    expect(await store.readDefaultsVersion(), 0);
    await store.writeDefaultsVersion(3);
    expect(await store.readDefaultsVersion(), 3);
  });

  test('the current flag is stored as one flag per group', () async {
    await store.saveGroups([group('a', current: true), group('b')]);
    expect((await store.loadGroups()).where((g) => g.current).single.id, 'a');

    await store.saveGroups([group('a'), group('b', current: true)]);
    expect((await store.loadGroups()).where((g) => g.current).single.id, 'b');
  });
}
