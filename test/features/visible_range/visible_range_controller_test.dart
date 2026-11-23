import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// The controller's persistence, seeding, group handling, lock gate and applied
/// targets.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late VisibleRangeController controller;

  final image = MimeFilter.image;
  final video = MimeFilter.video;
  const favourite = FavouriteFilter.instance;

  List<VisibleRangePresetDefinition> definitions() => [
    VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
    VisibleRangePresetDefinition(id: 'builtin.video', nameKey: 'visibleRangePresetVideo', filters: {video}),
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await controller.init();
  });

  tearDown(() => db.close());

  test('starts on the unrestricted default with the built-in groups seeded once', () async {
    expect(controller.gallery.name, isEmpty);
    expect(controller.gallery.rules, isEmpty);
    expect(controller.galleryFilter, isNull);
    expect(controller.galleryGroups, hasLength(3));
    expect(controller.galleryGroups.where((group) => isVisibleRangeBuiltinGroup(group.id)).map((group) => group.id), [
      visibleRangeBuiltinGroupId('builtin.image'),
      visibleRangeBuiltinGroupId('builtin.video'),
    ]);

    // A new connection on the same data must not duplicate.
    final second = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await second.init();
    expect(second.galleryGroups, hasLength(3));
  });

  test('a built-in group carries one source condition', () async {
    final group = controller.galleryGroupById(visibleRangeBuiltinGroupId('builtin.image'))!;
    expect(group.rulesOf(VisibleRangeRuleKind.source).single.filters, {image});
    expect(group.name, '@visibleRangePresetImage');
  });

  test('selecting a source persists and resolves', () async {
    await controller.selectBase(presetId: '', name: '', filters: {image});

    expect(controller.galleryFilter, image);
    expect(controller.galleryRestricted, isTrue);

    final reloaded = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryRangeId);
    expect(reloaded!.rulesOf(VisibleRangeRuleKind.source).single.filters, {image});
  });

  test('clearing the sources returns to unrestricted', () async {
    await controller.selectBase(presetId: '', name: '', filters: {image});
    await controller.clearSources();
    expect(controller.galleryFilter, isNull);
    expect(controller.galleryRestricted, isFalse);
  });

  test('switching groups changes the browsing filter', () async {
    await controller.selectGalleryGroup(visibleRangeBuiltinGroupId('builtin.video'));
    expect(controller.galleryFilter, video);
    expect(controller.currentGalleryGroupId, visibleRangeBuiltinGroupId('builtin.video'));
  });

  test('rules persist, toggle and delete', () async {
    final rule = await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {favourite});
    expect(rule, isNotNull);
    expect(controller.galleryFilter, favourite);

    await controller.toggleRule(rule!.id);
    expect(controller.gallery.ruleById(rule.id)!.active, isFalse);
    expect(controller.galleryFilter, isNull);

    await controller.deleteRules({rule.id});
    expect(controller.gallery.rules, isEmpty);
    expect((await VisibleRangeStore(db).loadRules(VisibleRange.galleryRangeId)), isEmpty);
  });

  test('adding an empty rule is a no-op', () async {
    expect(await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {}), isNull);
    expect(controller.gallery.rules, isEmpty);
  });

  test('the outside pool has no source role', () async {
    expect(await controller.addRule(kind: VisibleRangeRuleKind.source, filters: {image}, rangeId: controller.outside.id), isNull);
    expect(await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {favourite}, rangeId: controller.outside.id), isNotNull);
    expect(controller.galleryFilter, favourite);
    expect(controller.galleryRestricted, isTrue);
  });

  test('a locked gallery freezes group switching and edits', () async {
    final rule = await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {favourite});
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    expect(controller.locked, isTrue);
    expect(controller.canEdit, isFalse);
    await expectLater(controller.toggleRule(rule!.id), throwsStateError);
    await expectLater(controller.deleteRules({rule.id}), throwsStateError);
    await expectLater(controller.selectGalleryGroup(visibleRangeBuiltinGroupId('builtin.image')), throwsStateError);
    await expectLater(controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}, rangeId: controller.outside.id), throwsStateError);

    await controller.unlock();
    expect(controller.canEdit, isTrue);
  });

  test('quick lock reuses the last permissions preset', () async {
    await controller.lockWithPreset(VisibleRangeLockPreset.manageable);
    expect(controller.lastLockPreset, VisibleRangeLockPreset.manageable);
    expect(controller.gallery.permissions.edit, isTrue);

    await controller.unlock();
    await controller.lockWithPreset(controller.lastLockPreset);
    expect(controller.gallery.permissions.trash, isTrue);
  });

  test('the active conditions default to the section style', () async {
    expect(controller.activeStyle, VisibleRangeActiveStyle.section);
    expect(VisibleRangeActiveStyle.parse(null), VisibleRangeActiveStyle.section);
    expect(VisibleRangeActiveStyle.parse('compactChips'), VisibleRangeActiveStyle.compactChips);
    expect(VisibleRangeActiveStyle.parse('tiles'), VisibleRangeActiveStyle.tiles);
  });

  test('view preferences persist across a restart', () async {
    await controller.setActiveStyle(VisibleRangeActiveStyle.tiles);

    final restarted = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await restarted.init();
    expect(restarted.activeStyle, VisibleRangeActiveStyle.tiles);
  });

  test('the pinned injection mode is remembered only when asked', () async {
    await controller.setPinInjection(mode: VisibleRangeInjectionMode.park, remembered: true);
    final restarted = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await restarted.init();
    expect(restarted.pinInjectionRemembered, isTrue);
    expect(restarted.pinInjectionMode, VisibleRangeInjectionMode.park);
  });

  test('a defaults bump adds missing groups and keeps user work', () async {
    final userGroup = await controller.addGalleryGroup(name: 'Mine');

    // Pretend the install predates the current defaults version.
    final store = VisibleRangeStore(db);
    await store.writeState(VisibleRangeStore.keyDefaultsVersion, '1');
    await store.deleteRange(visibleRangeBuiltinGroupId('builtin.video'));

    final migrated = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await migrated.init();

    expect(migrated.galleryGroupById(visibleRangeBuiltinGroupId('builtin.video')), isNotNull);
    expect(migrated.galleryGroupById(userGroup.id)?.name, 'Mine');
    expect(await store.readState(VisibleRangeStore.keyDefaultsVersion), '${VisibleRangeStore.defaultsVersion}');
  });

  test('re-adding defaults skips groups that already exist', () async {
    final result = await controller.reAddDefaultPresets();
    expect(result.added, 0);
    expect(result.skipped, 2);
  });

  test('restriction and supplement defaults are seeded switched off in the outside pool', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final withRules = [
      VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
      VisibleRangePresetDefinition(id: 'builtin.restriction.image', nameKey: 'visibleRangePresetImage', kind: VisibleRangePresetKind.restriction, filters: {video}),
      VisibleRangePresetDefinition(id: 'builtin.supplement.favourite', nameKey: 'visibleRangePresetFavourite', kind: VisibleRangePresetKind.supplement, filters: {favourite}),
    ];
    final seeded = VisibleRangeController(injectedDatabase: fresh, presetLoader: () async => withRules);
    await seeded.init();

    final rules = seeded.outside.rules;
    expect(rules, hasLength(2));
    expect(rules.every((rule) => !rule.active), isTrue);
    expect(rules.map((rule) => rule.kind).toSet(), {VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement});
    expect(rules.every((rule) => rule.label.startsWith('@')), isTrue);
    // Seeded defaults never restrict the library by themselves.
    expect(seeded.gallery.isRestricted(outside: seeded.outside), isFalse);
  });

  test('a deleted outside default is restored switched off', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final withRules = [
      VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
      VisibleRangePresetDefinition(id: 'builtin.restriction.image', nameKey: 'visibleRangePresetImage', kind: VisibleRangePresetKind.restriction, filters: {video}),
    ];
    final seeded = VisibleRangeController(injectedDatabase: fresh, presetLoader: () async => withRules);
    await seeded.init();
    final rule = seeded.outside.rules.single;
    await seeded.deleteRules({rule.id});
    expect(seeded.outside.rules, isEmpty);

    final result = await seeded.reAddDefaultPresets();
    expect(result.added, 1);
    expect(seeded.outside.rules.single.id, rule.id);
    expect(seeded.outside.rules.single.active, isFalse);
  });
}
