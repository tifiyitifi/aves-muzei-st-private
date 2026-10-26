import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart' show VisibleRangeActiveStyle;
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// The wallpaper page's editor: group-scoped writes, the lock guard and its own
/// view preference.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupRangeController controller;

  List<WallpaperGroupDefinition> definitions() => [
        const WallpaperGroupDefinition(id: 'wallpaper.group.all', nameKey: 'wallpaperGroupDefaultAll', current: true),
        WallpaperGroupDefinition(id: 'wallpaper.group.dcim', nameKey: 'wallpaperGroupDefaultDcim', filters: {PathFilter('/dcim')}),
        WallpaperGroupDefinition(id: 'wallpaper.group.pictures', nameKey: 'wallpaperGroupDefaultPictures', filters: {PathFilter('/pictures')}),
      ];

  WallpaperGroupRangeController makeController() => WallpaperGroupRangeController(
        groupController: WallpaperGroupController(injectedDatabase: db, defaultLoader: () async => definitions()),
        injectedDatabase: db,
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = makeController();
    await controller.init();
  });

  tearDown(() => db.close());

  test('opens on the current group', () {
    expect(controller.groups, hasLength(3));
    expect(controller.selectedGroupId, 'wallpaper.group.all');
    expect(controller.range, isNotNull);
    expect(controller.range!.scope, VisibleRangeScope.wallpaper);
    expect(controller.range!.ownerId, 'wallpaper.group.all');
  });

  test('group 0 has no range to edit', () async {
    await controller.selectGroup(null);

    expect(controller.selectedGroupId, isNull);
    expect(controller.range, isNull);
    expect(controller.canEdit, isFalse);
  });

  test('selecting another group switches to its own range', () async {
    await controller.selectGroup('wallpaper.group.pictures');

    expect(controller.range!.ownerId, 'wallpaper.group.pictures');
    expect(controller.range!.baseFilters, {PathFilter('/pictures')});
    // The group it came from is untouched.
    final all = await controller.groupController.groupRange('wallpaper.group.all');
    expect(all.baseFilters, isEmpty);
  });

  test('writes go to the selected group only and persist', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.selectBase(presetId: 'builtin.image', name: 'visibleRangePresetImage', filters: {MimeFilter.image});

    expect(controller.range!.basePresetId, 'builtin.image');
    final stored = await controller.groupController.groupRange('wallpaper.group.dcim');
    expect(stored.basePresetId, 'builtin.image');
    expect(stored.baseFilters, {MimeFilter.image});
    // Other groups keep their own base.
    expect((await controller.groupController.groupRange('wallpaper.group.pictures')).baseFilters, {PathFilter('/pictures')});
  });

  test('clearing the base makes the group unrestricted', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.clearBase();

    expect(controller.range!.isBaseUnrestricted, isTrue);
    expect((await controller.groupController.groupRange('wallpaper.group.dcim')).isBaseUnrestricted, isTrue);
  });

  test('rules toggle, rename and reorder on the group range', () async {
    await controller.selectGroup('wallpaper.group.pictures');
    final range = controller.range!;
    final rule = VisibleRangeRule(
      id: 'r1',
      rangeId: range.id,
      kind: VisibleRangeRuleKind.restriction,
      filters: {MimeFilter.image},
      active: false,
    );
    await controller.groupController.saveGroupRange(range.copyWith(rules: [rule]));
    await controller.selectGroup('wallpaper.group.pictures');

    await controller.toggleRule('r1');
    expect(controller.range!.ruleById('r1')!.active, isTrue);

    await controller.renameRule('r1', label: 'Mine');
    expect(controller.range!.ruleById('r1')!.label, 'Mine');

    await controller.setOrder(VisibleRangeOrder.unionFirst);
    expect((await controller.groupController.groupRange('wallpaper.group.pictures')).order, VisibleRangeOrder.unionFirst);

    await controller.deleteRules({'r1'});
    expect(controller.range!.rules, isEmpty);
  });

  test('a locked range refuses edits', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.lockWithPreset(VisibleRangeLockPreset.readOnly);
    expect(controller.canEdit, isFalse);

    await controller.clearBase();
    // Still the seeded base: the lock guard stopped the write.
    expect(controller.range!.baseFilters, {PathFilter('/dcim')});

    await controller.unlock();
    expect(controller.canEdit, isTrue);
    await controller.clearBase();
    expect(controller.range!.isBaseUnrestricted, isTrue);
  });

  test('the active-style form is this page\'s own preference', () async {
    expect(controller.activeStyle, VisibleRangeActiveStyle.section);
    await controller.setActiveStyle(VisibleRangeActiveStyle.tiles);

    final restarted = makeController();
    await restarted.init();
    expect(restarted.activeStyle, VisibleRangeActiveStyle.tiles);

    // The visible-range page's key is a different one: the two pages stay
    // independent even though they share the store.
    final meta = await AppMetaStore(db).read({WallpaperGroupRangeController.keyActiveStyle, VisibleRangeStore.keyActiveStyle});
    expect(meta[WallpaperGroupRangeController.keyActiveStyle], VisibleRangeActiveStyle.tiles.name);
    expect(meta.containsKey(VisibleRangeStore.keyActiveStyle), isFalse);
  });
}
