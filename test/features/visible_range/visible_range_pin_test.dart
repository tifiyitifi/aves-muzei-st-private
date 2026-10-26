import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Pinning the current filters to one or more ranges/groups.
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // No bundled presets: the pin specs only care about the range itself.
    controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const []);
    await controller.init();
  });

  tearDown(() => db.close());

  VisibleRangePinRequest request({
    Set<CollectionFilter> filters = const {},
    String name = 'Pinned',
    String description = 'created at some point',
    Set<VisibleRangeCandidateKind> kinds = const {VisibleRangeCandidateKind.restriction},
    Set<String>? targets,
  }) {
    return VisibleRangePinRequest(
      filters: filters.isEmpty ? {image} : filters,
      name: name,
      description: description,
      kinds: kinds,
      targetRangeIds: targets ?? {VisibleRange.galleryRangeId},
    );
  }

  test('the gallery is the only registered target for now', () {
    final targets = controller.pinTargets;
    expect(targets, hasLength(1));
    final gallery = targets.single;
    expect(gallery.rangeId, VisibleRange.galleryRangeId);
    expect(gallery.number, 0);
    expect(gallery.isGallery, isTrue);
    expect(gallery.locked, isFalse);
  });

  test('pinning a restriction adds one active rule with name and description', () async {
    final result = await controller.pinFilters(request(name: 'Images', description: 'now'));

    expect(result.pinned, 1);
    expect(result.skipped, 0);
    final rule = controller.gallery.rules.single;
    expect(rule.kind, VisibleRangeRuleKind.restriction);
    expect(rule.label, 'Images');
    expect(rule.description, 'now');
    expect(rule.active, isTrue);
    expect(rule.filters, {image});
    expect(controller.galleryFilter, image);
  });

  test('pinning to restriction and supplement writes one rule per group', () async {
    await controller.pinFilters(request(kinds: {VisibleRangeCandidateKind.restriction, VisibleRangeCandidateKind.supplement}));

    final rules = controller.gallery.rules;
    expect(rules, hasLength(2));
    expect(rules.map((rule) => rule.id).toSet(), hasLength(2));
    expect(rules.map((rule) => rule.kind).toSet(), {VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement});
    expect(rules.every((rule) => rule.position == 0), isTrue);
    expect(rules.every((rule) => rule.active), isTrue);
  });

  test('re-pinning the same conditions updates the rule instead of stacking', () async {
    await controller.pinFilters(request(name: 'First', description: 'd1'));
    final first = controller.gallery.rules.single;
    await controller.toggleRule(first.id);
    expect(controller.gallery.ruleById(first.id)!.active, isFalse);

    await controller.pinFilters(request(name: 'Second', description: 'd2'));

    expect(controller.gallery.rules, hasLength(1));
    final updated = controller.gallery.rules.single;
    expect(updated.id, first.id);
    expect(updated.label, 'Second');
    expect(updated.description, 'd2');
    expect(updated.active, isTrue);
  });

  test('unknown or locked target ids are skipped', () async {
    final result = await controller.pinFilters(request(targets: {VisibleRange.galleryRangeId, 'wallpaper.1'}));
    expect(result.pinned, 1);
    expect(result.skipped, 1);
    expect(controller.gallery.rules, hasLength(1));

    final onlyUnknown = await controller.pinFilters(request(targets: {'wallpaper.1'}));
    expect(onlyUnknown.pinned, 0);
    expect(onlyUnknown.skipped, 1);
    expect(controller.gallery.rules, hasLength(1));
  });

  test('pinning a base creates a preset, selects it and reuses it on re-pin', () async {
    final result = await controller.pinFilters(
      request(filters: {image}, name: 'My base', description: 'first note', kinds: {VisibleRangeCandidateKind.base}),
    );
    expect(result.pinned, 1);

    final baseId = controller.gallery.basePresetId;
    expect(baseId, startsWith('user.'));
    var preset = controller.presets.singleWhere((p) => p.id == baseId);
    expect(preset.name, 'My base');
    expect(preset.description, 'first note');
    expect(preset.filters, {image});
    expect(controller.galleryFilter, image);

    await controller.pinFilters(
      request(filters: {image}, name: 'My base', description: 'second note', kinds: {VisibleRangeCandidateKind.base}),
    );

    // Same fingerprint + name reuses the preset and refreshes its note.
    expect(controller.presets.where((p) => !p.builtin), hasLength(1));
    preset = controller.presets.singleWhere((p) => p.id == controller.gallery.basePresetId);
    expect(preset.id, baseId);
    expect(preset.description, 'second note');
    expect(controller.gallery.baseName, 'My base');
  });

  test('a different name creates a second base preset for the same filters', () async {
    await controller.pinFilters(request(name: 'One', kinds: {VisibleRangeCandidateKind.base}));
    await controller.pinFilters(request(name: 'Two', kinds: {VisibleRangeCandidateKind.base}));
    final userPresets = controller.presets.where((p) => !p.builtin).toList();
    expect(userPresets, hasLength(2));
    expect(userPresets.map((p) => p.id).toSet(), hasLength(2));
  });

  test('base and restriction can be pinned in one request', () async {
    await controller.pinFilters(
      request(
        filters: {image},
        kinds: {VisibleRangeCandidateKind.base, VisibleRangeCandidateKind.restriction},
      ),
    );

    expect(controller.gallery.basePresetId, isNotEmpty);
    final restriction = controller.gallery.rules.single;
    expect(restriction.kind, VisibleRangeRuleKind.restriction);
    expect(restriction.filters, {image});
  });

  test('a locked range rejects pinning without writing anything', () async {
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    await expectLater(controller.pinFilters(request()), throwsStateError);
    expect(controller.gallery.rules, isEmpty);
    expect(controller.presets.where((p) => !p.builtin), isEmpty);
    expect(controller.pinTargets.single.locked, isTrue);
  });

  test('pinned rules and notes survive a restart', () async {
    await controller.pinFilters(request(name: 'Kept', description: 'keep me', kinds: {VisibleRangeCandidateKind.base, VisibleRangeCandidateKind.restriction}));
    final baseId = controller.gallery.basePresetId;

    final restarted = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const []);
    await restarted.init();

    expect(restarted.gallery.rules.single.label, 'Kept');
    expect(restarted.gallery.rules.single.description, 'keep me');
    expect(restarted.gallery.basePresetId, baseId);
    expect(restarted.presets.singleWhere((p) => p.id == baseId).description, 'keep me');
  });

  test('editing a user base preset updates its name and description', () async {
    await controller.pinFilters(request(name: 'Before', description: 'old', kinds: {VisibleRangeCandidateKind.base}));
    final presetId = controller.gallery.basePresetId;

    await controller.updateBasePreset(presetId, name: 'After', description: 'new');
    final preset = controller.presets.singleWhere((p) => p.id == presetId);

    expect(preset.name, 'After');
    expect(preset.description, 'new');
    expect(controller.gallery.baseName, 'After');

    // Built-in presets stay read-only.
    const builtin = VisibleRangePreset(id: 'builtin.image', name: 'visibleRangePresetImage', builtin: true);
    await controller.updateBasePreset(builtin.id, name: 'x', description: 'y');
    expect(controller.presets.where((p) => p.id == builtin.id), isEmpty);
  });

  test('an empty request is a no-op', () async {
    final result = await controller.pinFilters(const VisibleRangePinRequest(filters: {}, name: '', description: '', kinds: {}, targetRangeIds: {}));
    expect(result.pinned, 0);
    expect(result.skipped, 0);
    expect(controller.gallery.rules, isEmpty);
  });

  test('the video filter can be pinned independently of the image one', () async {
    await controller.pinFilters(request(filters: {video}));
    expect(controller.gallery.rules.single.filters, {video});
    expect(controller.galleryFilter, video);

    // Re-pinning a different condition adds another rule in the same group.
    await controller.pinFilters(request(filters: {favourite}));
    expect(controller.gallery.rules, hasLength(2));
    expect(controller.gallery.rules.map((rule) => rule.position), [0, 1]);
  });
}
