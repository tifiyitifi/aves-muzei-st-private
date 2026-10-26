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

/// The controller's persistence, seeding, lock gate and session lifecycle.
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

  test('starts unrestricted with the built-in presets seeded once', () async {
    expect(controller.gallery.isBaseUnrestricted, isTrue);
    expect(controller.galleryFilter, isNull);
    expect(controller.presets.map((p) => p.id), ['builtin.image', 'builtin.video']);

    // A new connection on the same data (same database) must not duplicate.
    final second = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await second.init();
    expect(second.presets, hasLength(2));
  });

  test('selecting a base persists and resolves', () async {
    final preset = controller.presets.first;
    await controller.selectBase(presetId: preset.id, name: preset.name, filters: preset.filters);

    expect(controller.gallery.basePresetId, 'builtin.image');
    expect(controller.galleryFilter, image);
    expect(controller.galleryRestricted, isTrue);

    final reloaded = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(reloaded!.baseFilters, {image});
  });

  test('clearing the base returns to unrestricted', () async {
    await controller.selectBase(presetId: 'builtin.image', name: 'x', filters: {image});
    await controller.clearBase();
    expect(controller.galleryFilter, isNull);
    expect(controller.galleryRestricted, isFalse);
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

  test('a locked range rejects edits', () async {
    final rule = await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {favourite});
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    expect(controller.locked, isTrue);
    expect(controller.canEdit, isFalse);
    await expectLater(controller.toggleRule(rule!.id), throwsStateError);
    await expectLater(controller.deleteRules({rule.id}), throwsStateError);

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

  test('view preferences persist across a restart', () async {
    await controller.setActiveStyle(VisibleRangeActiveStyle.tiles);

    final restarted = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
    await restarted.init();
    expect(restarted.activeStyle, VisibleRangeActiveStyle.tiles);
  });

  test('the active conditions default to the section style', () async {
    expect(controller.activeStyle, VisibleRangeActiveStyle.section);
    expect(VisibleRangeActiveStyle.parse(null), VisibleRangeActiveStyle.section);
    expect(VisibleRangeActiveStyle.parse('compactChips'), VisibleRangeActiveStyle.compactChips);
    expect(VisibleRangeActiveStyle.parse('tiles'), VisibleRangeActiveStyle.tiles);
  });

  test('a defaults bump reorders and prunes built-ins while keeping user state', () async {
    final legacyDb = AppDatabase(NativeDatabase.memory());
    addTearDown(legacyDb.close);
    final store = VisibleRangeStore(legacyDb);
    await store.writeState(VisibleRangeStore.keyDefaultsVersion, '2');
    await store.savePreset(VisibleRangePreset(id: 'builtin.recent3h', name: 'visibleRangePresetRecent3h', filters: {image}, builtin: true, position: 0));
    await store.savePreset(VisibleRangePreset(id: 'user.mine', name: 'Mine', filters: {video}, builtin: false, position: 1));

    VisibleRangeRule builtin(String id, VisibleRangeRuleKind kind, int position, {String label = '', bool active = false}) =>
        VisibleRangeRule(id: id, rangeId: VisibleRange.galleryRangeId, kind: kind, position: position, label: label, filters: {image}, active: active);

    await store.saveRange(
      VisibleRange.emptyGallery().copyWith(
        rules: [
          builtin('user.1', VisibleRangeRuleKind.restriction, 0),
          builtin('builtin.rule.builtin.restriction.video', VisibleRangeRuleKind.restriction, 7, label: 'My videos', active: true),
          // No longer shipped by the bundle: pruned together with its state.
          builtin('builtin.rule.builtin.restriction.notVideo', VisibleRangeRuleKind.restriction, 8),
          builtin('builtin.rule.builtin.supplement.image', VisibleRangeRuleKind.supplement, 0),
        ],
      ),
    );

    final migrated = VisibleRangeController(
      injectedDatabase: legacyDb,
      presetLoader: () async => [
        VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
        VisibleRangePresetDefinition(id: 'builtin.video', nameKey: 'visibleRangePresetVideo', filters: {video}),
        VisibleRangePresetDefinition(id: 'builtin.restriction.image', nameKey: 'visibleRangePresetImage', kind: VisibleRangePresetKind.restriction, filters: {image}),
        VisibleRangePresetDefinition(id: 'builtin.restriction.video', nameKey: 'visibleRangePresetVideo', kind: VisibleRangePresetKind.restriction, filters: {video}),
        VisibleRangePresetDefinition(id: 'builtin.supplement.recent12h', nameKey: 'visibleRangePresetRecent12h', kind: VisibleRangePresetKind.supplement, filters: {video}),
      ],
    );
    await migrated.init();

    final byId = {for (final rule in migrated.gallery.rules) rule.id: rule};
    // Kept defaults follow the bundle order but keep what the user made of them.
    expect(byId['builtin.rule.builtin.restriction.image']!.position, 0);
    expect(byId['builtin.rule.builtin.restriction.video']!.position, 1);
    expect(byId['builtin.rule.builtin.restriction.video']!.active, isTrue);
    expect(byId['builtin.rule.builtin.restriction.video']!.label, 'My videos');
    // A dropped default disappears with its activation state.
    expect(byId.containsKey('builtin.rule.builtin.restriction.notVideo'), isFalse);
    // A missing default is added inactive.
    expect(byId['builtin.rule.builtin.restriction.image']!.active, isFalse);
    expect(byId['builtin.rule.builtin.supplement.recent12h']!.active, isFalse);
    // User rules and presets keep their slots.
    expect(byId['user.1']!.position, 0);
    expect(migrated.presets.map((preset) => preset.id), containsAll(['builtin.image', 'builtin.video', 'user.mine']));
    expect(migrated.presets.map((preset) => preset.id), isNot(contains('builtin.recent3h')));
    expect(await store.readState(VisibleRangeStore.keyDefaultsVersion), '${VisibleRangeStore.defaultsVersion}');
  });

  test('re-adding defaults skips existing ids and fingerprints', () async {
    // Delete nothing; a second run must skip both.
    await controller.saveBasePreset(name: 'same filters', filters: {image});
    final result = await controller.reAddDefaultPresets();
    expect(result.added, 0);
    expect(result.skipped, 2);
  });

  test('restriction and supplement defaults are seeded switched off', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final withRules = [
      VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
      VisibleRangePresetDefinition(
        id: 'builtin.restriction.image',
        nameKey: 'visibleRangePresetImage',
        kind: VisibleRangePresetKind.restriction,
        filters: {video},
      ),
      VisibleRangePresetDefinition(
        id: 'builtin.supplement.favourite',
        nameKey: 'visibleRangePresetFavourite',
        kind: VisibleRangePresetKind.supplement,
        filters: {favourite},
      ),
    ];
    final seeded = VisibleRangeController(injectedDatabase: fresh, presetLoader: () async => withRules);
    await seeded.init();

    // Only base candidates are presets; the other sections are rules.
    expect(seeded.presets.map((preset) => preset.id), ['builtin.image']);
    final rules = seeded.gallery.rules;
    expect(rules, hasLength(2));
    expect(rules.every((rule) => !rule.active), isTrue);
    expect(rules.map((rule) => rule.kind).toSet(), {VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement});
    expect(rules.every((rule) => rule.label.startsWith('@')), isTrue);
    // Seeded defaults never restrict the library by themselves.
    expect(seeded.gallery.isRestricted, isFalse);
  });

  test('a deleted default is restored switched off', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final definitions = [
      VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
      VisibleRangePresetDefinition(
        id: 'builtin.restriction.image',
        nameKey: 'visibleRangePresetImage',
        kind: VisibleRangePresetKind.restriction,
        filters: {video},
      ),
    ];
    final seeded = VisibleRangeController(injectedDatabase: fresh, presetLoader: () async => definitions);
    await seeded.init();
    final rule = seeded.gallery.rules.single;
    await seeded.deleteRules({rule.id});
    expect(seeded.gallery.rules, isEmpty);

    final result = await seeded.reAddDefaultPresets();
    expect(result.added, 1);
    final restored = seeded.gallery.rules.single;
    expect(restored.id, rule.id);
    expect(restored.active, isFalse);
  });

  test('a defaults version bump replaces the default set but keeps user rules', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final first = [
      VisibleRangePresetDefinition(id: 'builtin.image', nameKey: 'visibleRangePresetImage', filters: {image}),
      VisibleRangePresetDefinition(
        id: 'builtin.restriction.image',
        nameKey: 'visibleRangePresetImage',
        kind: VisibleRangePresetKind.restriction,
        filters: {video},
      ),
    ];
    final firstController = VisibleRangeController(injectedDatabase: fresh, presetLoader: () async => first);
    await firstController.init();
    final userRule = (await firstController.addRule(kind: VisibleRangeRuleKind.supplement, filters: {favourite}))!;

    // Pretend the install predates the current defaults version.
    final store = VisibleRangeStore(fresh);
    await store.writeState(VisibleRangeStore.keyDefaultsVersion, '1');

    final second = [
      VisibleRangePresetDefinition(id: 'builtin.video', nameKey: 'visibleRangePresetVideo', filters: {video}),
    ];
    final secondController = VisibleRangeController(injectedDatabase: fresh, presetLoader: () async => second);
    await secondController.init();

    expect(secondController.presets.map((preset) => preset.id), ['builtin.video']);
    expect(secondController.gallery.ruleById(userRule.id)?.filters, {favourite});
    // The dropped built-in rule is gone; only the user rule remains.
    expect(secondController.gallery.rules, hasLength(1));
    expect(secondController.gallery.rules.single.id, userRule.id);
  });

  group('sessions', () {
    test('write-back applies only the session delta and clears every session', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      // The user opens the media set with the rule, then adds a video filter.
      await controller.beginActivation(rule: rule, mode: VisibleRangeActivationMode.override, resultingFilters: {image});
      await controller.closeOpenSession({image, video});
      expect(controller.sessions.single.added, {video});

      await controller.writeBackSession(controller.sessions.single.id);
      expect(controller.gallery.ruleById(rule.id)!.filters, {image, video});
      expect(controller.sessions, isEmpty);
    });

    test('a stale session does not overwrite a later one', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      await controller.beginActivation(rule: rule, mode: VisibleRangeActivationMode.override, resultingFilters: {image});
      await controller.closeOpenSession({image, favourite});
      await controller.beginActivation(rule: rule, mode: VisibleRangeActivationMode.override, resultingFilters: {image});
      await controller.closeOpenSession({image, video});

      // Both sessions stay addressable; writing one back clears all of them.
      expect(controller.sessions, hasLength(2));
      expect(controller.sessions.map((session) => session.id).toSet(), hasLength(2), reason: 'ids must stay unique even when created in the same millisecond');
      await controller.writeBackSession(controller.sessions.first.id);
      expect(controller.gallery.ruleById(rule.id)!.filters, {image, favourite});
      expect(controller.sessions, isEmpty);
    });

    test('saving without a write-back still clears sessions', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      await controller.beginActivation(rule: rule, mode: VisibleRangeActivationMode.append, resultingFilters: {favourite, image});
      await controller.closeOpenSession({favourite, image, video});
      await controller.clearSessions();
      expect(controller.sessions, isEmpty);
      expect(controller.gallery.ruleById(rule.id)!.filters, {image});
    });

    test('sessions survive a restart until saved', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      await controller.beginActivation(rule: rule, mode: VisibleRangeActivationMode.override, resultingFilters: {image});
      await controller.closeOpenSession({image, video});

      final restarted = VisibleRangeController(injectedDatabase: db, presetLoader: () async => definitions());
      await restarted.init();
      expect(restarted.sessions.single.added, {video});
    });
  });
}
