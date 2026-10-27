import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_usage.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_target_source.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Taking rules out to a media set, remembering the targets, and writing the
/// current filters back over them.
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
    controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const []);
    await controller.init();
  });

  tearDown(() => db.close());

  const groupRangeId = 'group.1.range';

  VisibleRange groupRange({List<VisibleRangeRule> rules = const [], bool locked = false}) => VisibleRange(
        id: groupRangeId,
        scope: VisibleRangeScope.wallpaper,
        ownerId: 'group.1',
        rules: rules,
        locked: locked,
        createdAt: 1,
        updatedAt: 1,
      );

  group('applied targets', () {
    test('taking a rule and a base out remembers both, deduped by id', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      await controller.selectBase(presetId: '', name: 'Mine', filters: {video});
      final base = VisibleRangeCandidate.customBase(name: 'Mine', filters: {video});

      await controller.markAppliedTargets(rangeId: controller.gallery.id, candidates: [VisibleRangeCandidate.fromRule(rule), base]);
      // Taking the same rule out again updates the row instead of adding one.
      await controller.markAppliedTargets(rangeId: controller.gallery.id, candidates: [VisibleRangeCandidate.fromRule(rule)]);

      final targets = await controller.loadAppliedTargets();
      expect(targets.map((target) => target.usageId).toSet(), {ruleUsageId(rule.id), baseUsageId(controller.gallery.id)});
      final ruleTarget = targets.singleWhere((target) => !target.isBase);
      expect(ruleTarget.label, isEmpty);
      expect(ruleTarget.filters, {image});
      expect(ruleTarget.isGallery, isTrue);
      final baseTarget = targets.singleWhere((target) => target.isBase);
      expect(baseTarget.label, 'Mine');
      expect(baseTarget.filters, {video});
    });

    test('a rule deleted from its range disappears from the list', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      await controller.markAppliedTargets(rangeId: controller.gallery.id, candidates: [VisibleRangeCandidate.fromRule(rule)]);
      await controller.deleteRules({rule.id});

      expect(await controller.loadAppliedTargets(), isEmpty);
    });

    test('write-back overwrites the selected rule and base only', () async {
      await controller.selectBase(presetId: 'builtin.image', name: 'Images', filters: {image});
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      final other = (await controller.addRule(kind: VisibleRangeRuleKind.supplement, filters: {favourite}))!;
      final base = VisibleRangeCandidate.customBase(name: 'Images', filters: {image});
      await controller.markAppliedTargets(rangeId: controller.gallery.id, candidates: [VisibleRangeCandidate.fromRule(rule), base]);

      final result = await controller.writeBackTargets(
        usageIds: {ruleUsageId(rule.id), baseUsageId(controller.gallery.id)},
        filters: {video},
        baseName: 'Night',
      );

      expect(result.written, 2);
      expect(result.skipped, 0);
      expect(controller.gallery.ruleById(rule.id)!.filters, {video});
      // Name, kind and position of the rule survive the overwrite.
      expect(controller.gallery.ruleById(rule.id)!.kind, VisibleRangeRuleKind.restriction);
      expect(controller.gallery.ruleById(rule.id)!.position, 0);
      // The unselected supplement is untouched.
      expect(controller.gallery.ruleById(other.id)!.filters, {favourite});
      // The base becomes this range's own base: the shared preset is not edited.
      expect(controller.gallery.baseFilters, {video});
      expect(controller.gallery.basePresetId, isEmpty);
      expect(controller.gallery.baseName, 'Night');
      expect(controller.presets, isEmpty);
    });

    test('a locked range is skipped and counted', () async {
      final rule = (await controller.addRule(kind: VisibleRangeRuleKind.restriction, filters: {image}))!;
      await controller.markAppliedTargets(rangeId: controller.gallery.id, candidates: [VisibleRangeCandidate.fromRule(rule)]);
      await controller.lock(permissions: VisibleRangePermissions.readOnly);

      final result = await controller.writeBackTargets(usageIds: {ruleUsageId(rule.id)}, filters: {video}, baseName: '');

      expect(result.written, 0);
      expect(result.skipped, 1);
      expect(controller.gallery.ruleById(rule.id)!.filters, {image});
    });

    test('an empty selection writes nothing', () async {
      final result = await controller.writeBackTargets(usageIds: const {}, filters: {video}, baseName: '');
      expect(result.written, 0);
      expect(result.skipped, 0);
    });
  });

  group('wallpaper groups', () {
    late _FakeTargetSource source;

    setUp(() {
      source = _FakeTargetSource({groupRangeId: groupRange()});
      controller.targetSource = source;
    });

    test('the pin sheet lists the gallery first, then the groups', () async {
      final targets = await controller.loadPinTargets();
      expect(targets.map((target) => target.isGallery), [true, false]);
      expect(targets.last.rangeId, groupRangeId);
      expect(targets.last.number, 2);
    });

    test('a pin request writes the gallery and the group in one visit', () async {
      final result = await controller.pinFilters(
        VisibleRangePinRequest(
          filters: {image},
          name: 'Pinned',
          description: 'now',
          kinds: const {VisibleRangeCandidateKind.restriction},
          targetRangeIds: {controller.gallery.id, groupRangeId},
        ),
      );

      expect(result.pinned, 2);
      expect(controller.gallery.rules.single.filters, {image});
      expect(source.ranges[groupRangeId]!.rules.single.filters, {image});
    });

    test('a locked group target is skipped, not failed', () async {
      source.ranges[groupRangeId] = groupRange(locked: true);
      final result = await controller.pinFilters(
        VisibleRangePinRequest(
          filters: {image},
          name: 'Pinned',
          description: 'now',
          kinds: const {VisibleRangeCandidateKind.restriction},
          targetRangeIds: const {groupRangeId},
        ),
      );
      expect(result.pinned, 0);
      expect(result.skipped, 1);
      expect(source.ranges[groupRangeId]!.rules, isEmpty);
    });

    test('a base pinned to a group is stored on the range, not in the preset catalog', () async {
      final result = await controller.pinFilters(
        VisibleRangePinRequest(
          filters: {image},
          name: 'Pinned base',
          description: 'now',
          kinds: const {VisibleRangeCandidateKind.base},
          targetRangeIds: const {groupRangeId},
        ),
      );

      expect(result.pinned, 1);
      final range = source.ranges[groupRangeId]!;
      expect(range.baseName, 'Pinned base');
      expect(range.baseFilters, {image});
      expect(range.baseActive, isTrue);
      expect(range.basePresetId, isEmpty);
      // The gallery's preset catalog is not involved at all.
      expect(controller.presets, isEmpty);
      expect(controller.gallery.baseFilters, isEmpty);
    });

    test('a group rule can be taken out and written back through the source', () async {
      final rule = VisibleRangeRule(id: 'g1', rangeId: groupRangeId, kind: VisibleRangeRuleKind.supplement, label: 'G', filters: {image});
      source.ranges[groupRangeId] = groupRange(rules: [rule]);
      await controller.markAppliedTargets(rangeId: groupRangeId, candidates: [VisibleRangeCandidate.fromRule(rule)]);

      final targets = await controller.loadAppliedTargets();
      expect(targets.single.isGallery, isFalse);
      expect(targets.single.number, 2);
      expect(targets.single.label, 'G');
      expect(targets.single.filters, {image});

      final result = await controller.writeBackTargets(usageIds: {ruleUsageId('g1')}, filters: {video}, baseName: '');
      expect(result.written, 1);
      expect(source.ranges[groupRangeId]!.ruleById('g1')!.filters, {video});
      expect(controller.gallery.rules, isEmpty);
    });
  });
}

/// A stand-in for the wallpaper-group source: the controller only sees ranges.
class _FakeTargetSource implements VisibleRangeTargetSource {
  final Map<String, VisibleRange> ranges;

  new(this.ranges);

  @override
  bool get targetsAreDraft => false;

  @override
  Future<List<VisibleRangePinTarget>> loadPinTargets() async => [
        for (final entry in ranges.entries)
          VisibleRangePinTarget(
            rangeId: entry.key,
            number: 2,
            name: '@wallpaperGroupDefaultDcim',
            isGallery: false,
            locked: entry.value.locked,
          ),
      ];

  @override
  Future<VisibleRange?> loadRange(String rangeId) async => ranges[rangeId];

  @override
  Future<void> saveRange(VisibleRange range) async => ranges[range.id] = range;
}
