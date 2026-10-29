import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_page_session.dart';
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
        groupController: WallpaperGroupController(
          injectedDatabase: db,
          defaultLoader: () async => definitions(),
        ),
        injectedDatabase: db,
      );

  setUp(() async {
    // The selected-group session is process-wide; a fresh test starts cold.
    wallpaperGroupPageSession
      ..initialized = false
      ..selectedGroupId = null;
    db = AppDatabase(NativeDatabase.memory());
    controller = makeController();
    await controller.init();
  });

  /// Seeds rules into [groupId]'s stored range and reloads the page on it.
  ///
  /// The page only edits rules that already exist (they arrive by pinning), so
  /// the tests have to put them there first.
  Future<void> seedRules(String groupId, List<VisibleRangeRule> Function(String rangeId) build) async {
    await controller.selectGroup(groupId);
    final range = controller.range!;
    await controller.groupController.saveGroupRange(range.copyWith(rules: build(range.id)));
    await controller.selectGroup(groupId);
  }

  tearDown(() => db.close());

  test('opens on group 1', () {
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

  test('writes go to the selected group only and persist on save', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.groupController.saveGroupRange(
      controller.range!.copyWith(basePresetId: 'builtin.image', baseName: 'Image', baseFilters: {MimeFilter.image}, baseActive: true),
    );

    expect(controller.range!.basePresetId, 'builtin.image');

    // The draft is not in the database until the page saves it.
    final updated = makeController();
    await updated.init();
    expect((await updated.groupController.groupRange('wallpaper.group.dcim')).basePresetId, isNot('builtin.image'));

    await controller.saveDraft();
    final restarted = makeController();
    await restarted.init();
    final stored = await restarted.groupController.groupRange('wallpaper.group.dcim');
    expect(stored.basePresetId, 'builtin.image');
    expect(stored.baseFilters, {MimeFilter.image});
    // Other groups keep their own base.
    expect((await restarted.groupController.groupRange('wallpaper.group.pictures')).baseFilters, {PathFilter('/pictures')});
  });

  test('clearing the base makes the group unrestricted', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.deleteConditions(base: true);

    expect(controller.range!.isBaseUnrestricted, isTrue);
    expect(controller.range!.baseFilters, isEmpty);
    expect((await controller.groupController.groupRange('wallpaper.group.dcim')).isBaseUnrestricted, isTrue);
  });

  test('switching the base off keeps its conditions for later', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.setBaseActive(false);

    expect(controller.range!.baseFilters, {PathFilter('/dcim')});
    expect(controller.range!.isBaseUnrestricted, isTrue);
    expect(controller.range!.resolve(), isNull);

    await controller.setBaseActive(true);
    expect(controller.range!.resolve(), PathFilter('/dcim'));
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

  test('updateRule replaces one rule and leaves the others alone', () async {
    await seedRules('wallpaper.group.pictures', (rangeId) => [
          VisibleRangeRule(id: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, filters: {MimeFilter.image}),
          VisibleRangeRule(id: 'r2', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, position: 1, filters: {MimeFilter.video}),
        ]);

    await controller.updateRule(controller.range!.ruleById('r1')!.copyWith(label: 'Mine', description: 'a note'));

    final updated = controller.range!.ruleById('r1')!;
    expect(updated.label, 'Mine');
    expect(updated.description, 'a note');
    expect(controller.range!.ruleById('r2')!.filters, {MimeFilter.video});
  });

  test('moveRuleToKind appends the rule to the target section', () async {
    await seedRules('wallpaper.group.pictures', (rangeId) => [
          VisibleRangeRule(id: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, filters: {MimeFilter.image}, label: 'Mine', active: false),
          VisibleRangeRule(id: 'r2', rangeId: rangeId, kind: VisibleRangeRuleKind.supplement, filters: {MimeFilter.video}),
        ]);

    await controller.moveRuleToKind('r1', VisibleRangeRuleKind.supplement);

    final moved = controller.range!.ruleById('r1')!;
    expect(moved.kind, VisibleRangeRuleKind.supplement);
    // Appended after the supplement that was already there.
    expect(moved.position, 1);
    // Only the section changes: the rule keeps its own conditions and toggle.
    expect(moved.label, 'Mine');
    expect(moved.active, isFalse);
    expect(moved.filters, {MimeFilter.image});

    await controller.moveRuleToKind('r1', VisibleRangeRuleKind.restriction);
    expect(controller.range!.ruleById('r1')!.position, 0);
  });

  test('moveRuleToBase turns a rule into the base', () async {
    await seedRules('wallpaper.group.all', (rangeId) => [
          VisibleRangeRule(id: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.supplement, filters: {MimeFilter.video}),
        ]);

    await controller.moveRuleToBase('r1', name: ' Videos ');

    final range = controller.range!;
    expect(range.baseName, 'Videos');
    expect(range.basePresetId, '');
    expect(range.baseFilters, {MimeFilter.video});
    expect(range.baseActive, isTrue);
    expect(range.rules, isEmpty);
  });

  test('moveRuleToBase overwrites an existing base', () async {
    await seedRules('wallpaper.group.pictures', (rangeId) => [
          VisibleRangeRule(id: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, filters: {MimeFilter.image}),
        ]);

    await controller.moveRuleToBase('r1', name: 'Images');

    final range = controller.range!;
    expect(range.baseName, 'Images');
    // The base is one slot: the seeded /pictures conditions are replaced.
    expect(range.baseFilters, {MimeFilter.image});
    expect(range.rules, isEmpty);
  });

  test('a locked range refuses the rule actions too', () async {
    await seedRules('wallpaper.group.pictures', (rangeId) => [
          VisibleRangeRule(id: 'r1', rangeId: rangeId, kind: VisibleRangeRuleKind.restriction, filters: {MimeFilter.image}),
        ]);
    await controller.lockWithPreset(VisibleRangeLockPreset.readOnly);

    await controller.updateRule(controller.range!.ruleById('r1')!.copyWith(label: 'Nope'));
    expect(controller.range!.ruleById('r1')!.label, isEmpty);

    await controller.moveRuleToBase('r1', name: 'Nope');
    expect(controller.range!.rules, hasLength(1));
    expect(controller.range!.baseFilters, {PathFilter('/pictures')});
  });

  test('locking with custom permissions stores each one', () async {
    await controller.selectGroup('wallpaper.group.pictures');
    const permissions = VisibleRangePermissions(
      share: false,
      delete: true,
      edit: false,
      move: true,
      rename: false,
      hide: true,
      vault: false,
      trash: true,
      metadata: false,
    );
    await controller.lock(permissions: permissions);

    expect(controller.range!.locked, isTrue);
    expect(controller.range!.permissions, permissions);

    await controller.saveDraft();
    final restarted = makeController();
    await restarted.init();
    await restarted.selectGroup('wallpaper.group.pictures');
    expect(restarted.range!.locked, isTrue);
    expect(restarted.range!.permissions, permissions);
  });

  test('a locked range refuses edits', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.lockWithPreset(VisibleRangeLockPreset.readOnly);
    expect(controller.canEdit, isFalse);

    await controller.deleteConditions(base: true);
    // Still the seeded base: the lock guard stopped the write.
    expect(controller.range!.baseFilters, {PathFilter('/dcim')});

    await controller.unlock();
    expect(controller.canEdit, isTrue);
    await controller.deleteConditions(base: true);
    expect(controller.range!.isBaseUnrestricted, isTrue);
  });

  test('the active-style form is this page\'s own preference', () async {    expect(controller.activeStyle, VisibleRangeActiveStyle.section);
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

  test('adding a group opens it', () async {
    await controller.addGroup(name: 'Trips');

    final added = controller.groups.last;
    expect(added.name, 'Trips');
    expect(controller.selectedGroupId, added.id);
    expect(controller.range!.ownerId, added.id);
    expect(controller.range!.isBaseUnrestricted, isTrue);
  });

  test('deleting the selected group moves the page to another group', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    expect(await controller.deleteGroup('wallpaper.group.dcim'), isTrue);

    expect(controller.groups.map((group) => group.id), ['wallpaper.group.all', 'wallpaper.group.pictures']);
    expect(controller.selectedGroupId, isNotNull);
    expect(controller.range!.ownerId, controller.selectedGroupId);
    expect(controller.range!.ownerId, isNot('wallpaper.group.dcim'));
  });

  test('deleting a group that is not selected keeps the current selection', () async {
    await controller.selectGroup('wallpaper.group.pictures');
    await controller.deleteGroup('wallpaper.group.dcim');

    expect(controller.selectedGroupId, 'wallpaper.group.pictures');
    expect(controller.range!.ownerId, 'wallpaper.group.pictures');
  });

  test('the last group cannot be deleted', () async {
    await controller.deleteGroup('wallpaper.group.dcim');
    await controller.deleteGroup('wallpaper.group.pictures');

    expect(await controller.deleteGroup('wallpaper.group.all'), isFalse);
    expect(controller.groups, hasLength(1));
  });

  test('deleting several groups from the page falls back to another viewed group', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    expect(await controller.deleteGroups({'wallpaper.group.dcim', 'wallpaper.group.pictures'}), isTrue);

    expect(controller.groups.map((group) => group.id), ['wallpaper.group.all']);
    expect(controller.selectedGroupId, 'wallpaper.group.all');
    expect(controller.range!.ownerId, 'wallpaper.group.all');
    expect(controller.dirty, isTrue);
  });

  test('group management reaches the controller and persists on save', () async {
    await controller.updateGroup('wallpaper.group.all', name: 'Everything', description: 'my trips');
    expect(controller.groups.first.name, 'Everything');
    expect(controller.groups.first.description, 'my trips');

    await controller.selectCurrent('wallpaper.group.pictures');
    expect(controller.current.id, 'wallpaper.group.pictures');

    await controller.setEnabled('wallpaper.group.all', false);
    expect(controller.groups.last.id, 'wallpaper.group.all');
    expect(controller.groups.last.enabled, isFalse);

    await controller.moveGroup('wallpaper.group.pictures', -1);
    expect(controller.groups.first.id, 'wallpaper.group.pictures');

    await controller.saveDraft();
    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups.first.id, 'wallpaper.group.pictures');
    expect(restarted.groups.last.name, 'Everything');
    expect(restarted.groups.last.description, 'my trips');
    expect(restarted.current.id, 'wallpaper.group.pictures');
  });

  test('adding a group stores its description', () async {
    await controller.addGroup(name: 'Trips', description: 'created today');
    expect(controller.groups.last.description, 'created today');
    expect((await controller.groupController.groupRange(controller.groups.last.id)).isBaseUnrestricted, isTrue);
  });

  test('discarding the draft restores the saved groups and ranges', () async {
    await controller.selectGroup('wallpaper.group.dcim');
    await controller.deleteConditions(base: true);
    await controller.updateGroup('wallpaper.group.all', name: 'Renamed');
    expect(controller.dirty, isTrue);

    await controller.discardDraft();
    expect(controller.dirty, isFalse);
    expect(controller.selectedGroupId, 'wallpaper.group.dcim');
    expect(controller.range!.baseFilters, {PathFilter('/dcim')});
    expect(controller.groups.first.name, '@wallpaperGroupDefaultAll');
  });

  test('the group switcher style is this page\'s own preference', () async {
    expect(controller.switcherStyle, WallpaperGroupSwitcherStyle.chips);
    await controller.setSwitcherStyle(WallpaperGroupSwitcherStyle.sections);

    final restarted = makeController();
    await restarted.init();
    expect(restarted.switcherStyle, WallpaperGroupSwitcherStyle.sections);

    // The visible-range page keeps its own keys: nothing leaked into them.
    final meta = await AppMetaStore(db).read({WallpaperGroupRangeController.keySwitcherStyle, VisibleRangeStore.keyActiveStyle});
    expect(meta[WallpaperGroupRangeController.keySwitcherStyle], WallpaperGroupSwitcherStyle.sections.name);
    expect(meta.containsKey(VisibleRangeStore.keyActiveStyle), isFalse);
  });

  test('a cold start opens group 1 even when the wallpaper uses another group', () async {
    await controller.selectCurrent('wallpaper.group.pictures');
    await controller.saveDraft();

    wallpaperGroupPageSession
      ..initialized = false
      ..selectedGroupId = null;
    final cold = makeController();
    await cold.init();
    expect(cold.selectedGroupId, 'wallpaper.group.all');
    expect(cold.current.id, 'wallpaper.group.pictures');
  });

  test('the selected group survives a rebuilt page but not a cold start', () async {
    await controller.selectGroup('wallpaper.group.pictures');

    // Rebuilding the page (backgrounding, another tab, coming back) resumes it.
    final rebuilt = makeController();
    await rebuilt.init();
    expect(rebuilt.selectedGroupId, 'wallpaper.group.pictures');

    // A process death clears the in-memory session: the page opens on group 1,
    // since the wallpaper feature may never have been visited.
    wallpaperGroupPageSession
      ..initialized = false
      ..selectedGroupId = null;
    final cold = makeController();
    await cold.init();
    expect(cold.selectedGroupId, 'wallpaper.group.all');
  });
}
