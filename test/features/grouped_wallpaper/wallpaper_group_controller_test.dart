import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Seeding from the bundle, the group invariants across restarts, and the
/// per-group range guard.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupController controller;

  List<WallpaperGroupDefinition> definitions({bool resolvable = true}) => [
        const WallpaperGroupDefinition(id: 'wallpaper.group.all', nameKey: 'wallpaperGroupDefaultAll', current: true),
        if (resolvable)
          WallpaperGroupDefinition(id: 'wallpaper.group.dcim', nameKey: 'wallpaperGroupDefaultDcim', filters: {PathFilter('/dcim')})
        else
          WallpaperGroupDefinition(id: 'wallpaper.group.dcim', nameKey: 'wallpaperGroupDefaultDcim', filters: {wallpaperDenyAllFilter()}),
        WallpaperGroupDefinition(id: 'wallpaper.group.pictures', nameKey: 'wallpaperGroupDefaultPictures', filters: {PathFilter('/pictures')}),
      ];

  WallpaperGroupController makeController({List<WallpaperGroupDefinition>? bundle}) => WallpaperGroupController(
        injectedDatabase: db,
        defaultLoader: () async => bundle ?? definitions(),
      );

  /// The shipped bundle's order and declared current group (Pictures = 1).
  List<WallpaperGroupDefinition> picturesCurrentBundle() => [
        WallpaperGroupDefinition(id: 'wallpaper.group.pictures', nameKey: 'wallpaperGroupDefaultPictures', current: true, filters: {PathFilter('/pictures')}),
        WallpaperGroupDefinition(id: 'wallpaper.group.dcim', nameKey: 'wallpaperGroupDefaultDcim', filters: {PathFilter('/dcim')}),
        const WallpaperGroupDefinition(id: 'wallpaper.group.all', nameKey: 'wallpaperGroupDefaultAll'),
      ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = makeController();
    await controller.init();
  });

  tearDown(() => db.close());

  test('seeds the bundled groups once with the bundle order and current group', () async {
    expect(controller.groups.map((group) => group.id), [
      'wallpaper.group.all',
      'wallpaper.group.dcim',
      'wallpaper.group.pictures',
    ]);
    expect(controller.groups.map((group) => group.number), [1, 2, 3]);
    expect(controller.groups.map((group) => group.enabled), everyElement(isTrue));
    expect(controller.current.id, 'wallpaper.group.all');
    // Bundled names are ARB keys, so they follow the app language.
    expect(controller.groups.first.name, '@wallpaperGroupDefaultAll');
    expect(controller.groups.first.hasBundledName, isTrue);

    final range = await controller.groupRange('wallpaper.group.dcim');
    expect(range.scope, VisibleRangeScope.wallpaper);
    expect(range.ownerId, 'wallpaper.group.dcim');
    expect(range.baseFilters, {PathFilter('/dcim')});

    // A second start must not duplicate them.
    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups, hasLength(3));
  });

  test('seeds each group with its exclusive base and no rules', () async {
    final dcim = await controller.groupRange('wallpaper.group.dcim');
    // A wallpaper group does not copy the gallery's restriction/supplement
    // catalogue: it starts with its one base.
    expect(dcim.rules, isEmpty);

    final all = await controller.groupRange('wallpaper.group.all');
    expect(all.rules, isEmpty);
    expect(all.baseFilters, isEmpty);
  });

  test('a group whose folder was not resolvable is seeded closed', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final seeded = WallpaperGroupController(injectedDatabase: fresh, defaultLoader: () async => definitions(resolvable: false));
    await seeded.init();

    final range = await seeded.groupRange('wallpaper.group.dcim');
    expect(range.isRestricted, isTrue);
    expect(range.baseFilters.single, wallpaperDenyAllFilter());
  });

  test('renaming a group survives a restart and a defaults re-apply', () async {
    await controller.updateGroup('wallpaper.group.dcim', name: 'Trips', description: 'summer');
    expect(controller.groups[1].name, 'Trips');
    expect(controller.groups[1].hasBundledName, isFalse);

    // A defaults bump re-applies the bundle but must not overwrite the name or
    // the description.
    await WallpaperGroupStore(db).writeDefaultsVersion(0);
    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups[1].name, 'Trips');
    expect(restarted.groups[1].description, 'summer');
  });

  test('a defaults bump moves an untouched seeded current group to the new default', () async {
    // Bundle v2 declared 「All」 as current, the shipped bundle declares
    // 「Pictures」: an install that never picked another group follows the bundle.
    expect(controller.current.id, 'wallpaper.group.all');

    await WallpaperGroupStore(db).writeDefaultsVersion(WallpaperGroupController.defaultsVersion - 1);
    final restarted = makeController(bundle: picturesCurrentBundle());
    await restarted.init();

    expect(restarted.current.id, 'wallpaper.group.pictures');
    expect(restarted.groups.map((group) => group.id), [
      'wallpaper.group.pictures',
      'wallpaper.group.dcim',
      'wallpaper.group.all',
    ]);
    expect(restarted.groups.map((group) => group.number), [1, 2, 3]);
    // Reordering the bundle must not rewrite a group's own range.
    expect((await restarted.groupRange('wallpaper.group.pictures')).baseFilters, {PathFilter('/pictures')});
  });

  test('a defaults bump keeps a current group the user picked', () async {
    await controller.selectCurrent('wallpaper.group.dcim');

    await WallpaperGroupStore(db).writeDefaultsVersion(WallpaperGroupController.defaultsVersion - 1);
    final restarted = makeController(bundle: picturesCurrentBundle());
    await restarted.init();

    expect(restarted.current.id, 'wallpaper.group.dcim');
  });

  test('seeded rules from older versions are pruned on every start', () async {
    // Simulate an older install: a group range carrying the old gallery
    // candidates, one of them switched on by the user and one renamed. The
    // defaults marker is already current, so only an unconditional prune can
    // keep the group page free of the gallery's catalogue.
    final range = await controller.groupRange('wallpaper.group.dcim');
    VisibleRangeRule seeded(String suffix, {bool active = false, String? label}) => VisibleRangeRule(
          id: 'wallpaper.group.dcim.rule.$suffix',
          rangeId: range.id,
          kind: VisibleRangeRuleKind.restriction,
          label: label ?? '@visibleRangePresetImage',
          filters: {MimeFilter.image},
          active: active,
        );
    final userRule = VisibleRangeRule(id: 'user.rule', rangeId: range.id, kind: VisibleRangeRuleKind.supplement, label: 'Mine', filters: {MimeFilter.video});
    await controller.saveGroupRange(
      range.copyWith(rules: [
        seeded('builtin.restriction.image'),
        seeded('builtin.restriction.video', active: true),
        seeded('builtin.restriction.raw', label: 'My RAW'),
        userRule,
      ]),
    );
    await WallpaperGroupStore(db).writeDefaultsVersion(WallpaperGroupController.defaultsVersion);

    final restarted = makeController();
    await restarted.init();
    final rules = (await restarted.groupRange('wallpaper.group.dcim')).rules;
    // The inactive untouched default goes; the user's activation, the rename and
    // the user rule stay.
    expect(rules.map((rule) => rule.id).toSet(), {
      'wallpaper.group.dcim.rule.builtin.restriction.video',
      'wallpaper.group.dcim.rule.builtin.restriction.raw',
      'user.rule',
    });
  });

  test('deleting a middle group renumbers and keeps the current group', () async {
    await controller.selectCurrent('wallpaper.group.pictures');
    expect(await controller.deleteGroup('wallpaper.group.dcim'), isTrue);

    expect(controller.groups.map((group) => group.id), ['wallpaper.group.all', 'wallpaper.group.pictures']);
    expect(controller.groups.map((group) => group.number), [1, 2]);
    expect(controller.current.id, 'wallpaper.group.pictures');
    expect(await controller.groupRange('wallpaper.group.dcim'), isA<VisibleRange>());
  });

  test('the last group cannot be deleted', () async {
    await controller.deleteGroup('wallpaper.group.dcim');
    await controller.deleteGroup('wallpaper.group.pictures');
    expect(controller.groups, hasLength(1));
    expect(await controller.deleteGroup('wallpaper.group.all'), isFalse);
    expect(controller.groups, hasLength(1));
  });

  test('deleting several groups is one draft change and refuses to empty the list', () async {
    await controller.beginDraft();
    expect(await controller.deleteGroups({'wallpaper.group.dcim', 'wallpaper.group.pictures'}), isTrue);
    expect(controller.groups.map((group) => group.id), ['wallpaper.group.all']);
    expect(controller.dirty, isTrue);

    // The draft is not in the database until it is saved.
    final reader = makeController();
    await reader.init();
    expect(reader.groups, hasLength(3));

    // A selection that would remove every group is refused as a whole.
    expect(await controller.deleteGroups({'wallpaper.group.all'}), isFalse);
    expect(controller.groups, hasLength(1));

    await controller.saveDraft();
    final saved = makeController();
    await saved.init();
    expect(saved.groups.map((group) => group.id), ['wallpaper.group.all']);
    expect(await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'wallpaper.group.dcim'), isNull);
    expect(await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'wallpaper.group.pictures'), isNull);
  });

  test('disabling the current group falls back to group 0', () async {
    await controller.setEnabled('wallpaper.group.all', false);

    expect(controller.current.isNone, isTrue);
    expect(controller.groups.last.id, 'wallpaper.group.all');
    expect(controller.enabledGroups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.pictures']);
  });

  test('enabling a group moves it to the end of the enabled segment', () async {
    await controller.setEnabled('wallpaper.group.all', false);
    await controller.setEnabled('wallpaper.group.all', true);

    expect(controller.groups.last.id, 'wallpaper.group.all');
    expect(controller.enabledGroups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.pictures', 'wallpaper.group.all']);
    // The current flag was cleared when it was disabled; re-enabling does not
    // silently make it current again.
    expect(controller.current.isNone, isTrue);
  });

  test('moving a group stays inside its segment and persists', () async {
    await controller.moveGroup('wallpaper.group.dcim', -1);
    expect(controller.groups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.all', 'wallpaper.group.pictures']);

    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.all', 'wallpaper.group.pictures']);
  });

  test('a new group is appended, unrestricted and independent', () async {    await controller.addGroup(name: 'Trips', description: 'created today');
    final added = controller.groups.last;

    expect(added.id, isNot(startsWith('wallpaper.group.')));
    expect(added.name, 'Trips');
    expect(added.description, 'created today');
    expect(added.number, 4);
    expect(controller.groups.first.id, 'wallpaper.group.all');

    final range = await controller.groupRange(added.id);
    expect(range.baseFilters, isEmpty);
    expect(range.rules, isEmpty);

    await controller.saveGroupRange(range.copyWith(baseFilters: {PathFilter('/trips')}));
    expect((await controller.groupRange(added.id)).baseFilters, {PathFilter('/trips')});
    // Other groups are untouched.
    expect((await controller.groupRange('wallpaper.group.pictures')).baseFilters, {PathFilter('/pictures')});
  });

  test('a group range must belong to a known group and the wallpaper scope', () async {
    final range = await controller.groupRange('wallpaper.group.dcim');

    await controller.saveGroupRange(range.copyWith(baseFilters: {PathFilter('/x')}));
    expect((await controller.groupRange('wallpaper.group.dcim')).baseFilters, {PathFilter('/x')});

    await expectLater(
      controller.saveGroupRange(
        const VisibleRange(id: 'gallery', scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId),
      ),
      throwsArgumentError,
    );
    await expectLater(
      controller.saveGroupRange(const VisibleRange(id: 'unknown.range', scope: VisibleRangeScope.wallpaper, ownerId: 'unknown')),
      throwsArgumentError,
    );
    await expectLater(
      controller.saveGroupRange(const VisibleRange(id: 'mismatch', scope: VisibleRangeScope.wallpaper, ownerId: 'wallpaper.group.dcim')),
      throwsArgumentError,
    );
  });

  test('saving a group range bumps the group timestamp and notifies', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    final range = await controller.groupRange('wallpaper.group.all');
    await controller.saveGroupRange(range.copyWith(baseFilters: {MimeFilter.image}));

    expect(notified, 1);
    expect(controller.groups.first.updatedAt, greaterThan(0));
  });

  test('the draft keeps edits in memory until saved', () async {
    await controller.beginDraft();
    await controller.updateGroup('wallpaper.group.dcim', name: 'Draft name');
    final range = await controller.groupRange('wallpaper.group.dcim');
    await controller.saveGroupRange(range.copyWith(baseFilters: {PathFilter('/draft')}, baseActive: true));
    await controller.deleteGroup('wallpaper.group.pictures');
    expect(controller.dirty, isTrue);
    expect(controller.groups, hasLength(2));

    // A controller without the draft reads the saved state.
    final reader = makeController();
    await reader.init();
    expect(reader.groups[1].name, isNot('Draft name'));
    expect(reader.groups, hasLength(3));
    expect((await reader.groupRange('wallpaper.group.dcim')).baseFilters, {PathFilter('/dcim')});

    await controller.saveDraft();
    expect(controller.dirty, isFalse);

    final saved = makeController();
    await saved.init();
    expect(saved.groups[1].name, 'Draft name');
    expect(saved.groups, hasLength(2));
    expect((await saved.groupRange('wallpaper.group.dcim')).baseFilters, {PathFilter('/draft')});
    // The deleted group and its range are gone.
    expect(await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'wallpaper.group.pictures'), isNull);
  });

  test('discarding the draft restores the saved state', () async {
    await controller.beginDraft();
    await controller.updateGroup('wallpaper.group.dcim', name: 'Draft name');
    final range = await controller.groupRange('wallpaper.group.dcim');
    await controller.saveGroupRange(range.copyWith(baseActive: false));
    expect(controller.dirty, isTrue);

    await controller.discardDraft();
    expect(controller.dirty, isFalse);
    expect(controller.groups[1].name, '@wallpaperGroupDefaultDcim');
    final restored = await controller.groupRange('wallpaper.group.dcim');
    expect(restored.baseFilters, {PathFilter('/dcim')});
    expect(restored.baseActive, isTrue);
  });

  test('setAutoAdvance writes one group without bumping its timestamp', () async {
    const id = 'wallpaper.group.dcim';
    final before = controller.groups.firstWhere((group) => group.id == id);

    await controller.setAutoAdvance(id, interval: WallpaperInterval.h3, ordering: GroupedWallpaperOrdering.inOrder);

    final after = controller.groups.firstWhere((group) => group.id == id);
    expect(after.interval, WallpaperInterval.h3);
    expect(after.ordering, GroupedWallpaperOrdering.inOrder);
    // The contract only affects future picks, so the frame on screen survives.
    expect(after.updatedAt, before.updatedAt);
    final stored = (await WallpaperGroupStore(db).loadGroups()).firstWhere((group) => group.id == id);
    expect(stored.interval, WallpaperInterval.h3);
    expect(stored.ordering, GroupedWallpaperOrdering.inOrder);
    // The other groups keep their own contract.
    expect(controller.groups.firstWhere((group) => group.id != id).interval, WallpaperInterval.never);
  });

  test('reloadSaved picks up a group switched by another surface', () async {
    final stored = await WallpaperGroupStore(db).loadGroups();
    final target = stored.last;
    expect(controller.current.id, isNot(target.id));
    await WallpaperGroupStore(db).saveGroups([
      for (final group in stored) group.copyWith(current: group.id == target.id),
    ]);

    await controller.reloadSaved();

    expect(controller.current.id, target.id);
  });

  test('reloadSaved leaves an unsaved draft alone', () async {
    await controller.beginDraft();
    await controller.updateGroup('wallpaper.group.dcim', name: 'Draft name');
    final stored = await WallpaperGroupStore(db).loadGroups();
    await WallpaperGroupStore(db).saveGroups([
      for (final group in stored) group.copyWith(current: group.id == 'wallpaper.group.pictures'),
    ]);

    await controller.reloadSaved();

    // The dirty draft owns the list until it is saved or discarded.
    expect(controller.groups.firstWhere((group) => group.id == 'wallpaper.group.dcim').name, 'Draft name');
  });

  test('the replacement warning needs a wallpaper that was really on', () async {
    // Never set: the page prepares frames for the picker preview too, so a frame
    // alone must not look like a replaced wallpaper.
    expect(await controller.takeOverwriteWarning(active: false, disabled: false, hasFrame: true), isFalse);

    // Seen on screen once, then gone: that is the replacement.
    expect(await controller.takeOverwriteWarning(active: true, disabled: false, hasFrame: true), isFalse);
    expect(await controller.takeOverwriteWarning(active: false, disabled: false, hasFrame: true), isTrue);
    // One warning per replacement, even without the dialog being dismissed.
    expect(await controller.takeOverwriteWarning(active: false, disabled: false, hasFrame: true), isFalse);
  });

  test('the replacement warning respects the off switch and the opt-out', () async {
    await controller.takeOverwriteWarning(active: true, disabled: false, hasFrame: true);
    // Turned off by the user: nothing surprising happened.
    expect(await controller.takeOverwriteWarning(active: false, disabled: true, hasFrame: true), isFalse);
    expect(await controller.takeOverwriteWarning(active: false, disabled: false, hasFrame: true), isFalse);

    await controller.takeOverwriteWarning(active: true, disabled: false, hasFrame: true);
    await controller.dismissOverwriteWarning();
    expect(await controller.takeOverwriteWarning(active: false, disabled: false, hasFrame: true), isFalse);
  });
}
