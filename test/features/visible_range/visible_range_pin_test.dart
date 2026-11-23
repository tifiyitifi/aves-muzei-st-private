import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Pinning the current filters to a group or to the outside pool.
void main() {
  late PathFilter albumA;

  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
    albumA = PathFilter('/a');
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
    // Group 0 is 「Unrestricted」 and never a write target: every pin test writes
    // into a data group, which is also what the save sheet preselects.
    await controller.addGalleryGroup(name: 'G1');
  });

  tearDown(() => db.close());

  VisibleRangePinRequest request({
    Set<CollectionFilter> filters = const {},
    String name = 'Pinned',
    String description = 'created at some point',
    Set<String>? targets,
    VisibleRangeInjectionMode injection = VisibleRangeInjectionMode.auto,
    VisibleRangeRuleKind? forcedRole,
    VisibleRangePinWriteMode writeMode = VisibleRangePinWriteMode.append,
  }) {
    return VisibleRangePinRequest(
      filters: filters.isEmpty ? {image} : filters,
      name: name,
      description: description,
      targetIds: targets ?? {controller.currentGalleryGroupId},
      injection: injection,
      forcedRole: forcedRole,
      writeMode: writeMode,
    );
  }

  test('the group plus the two outside roles are the targets without a registered source', () async {
    final targets = await controller.loadPinTargets();
    expect(targets, hasLength(3));
    expect(targets.where((target) => target.kind == VisibleRangePinTargetKind.galleryGroup), hasLength(1));
    expect(targets.where((target) => target.kind == VisibleRangePinTargetKind.outside).map((target) => target.role), [
      VisibleRangeRuleKind.restriction,
      VisibleRangeRuleKind.supplement,
    ]);
    expect(targets.first.number, 1);
    expect(targets.first.locked, isFalse);
  });

  test('pinning a media type into an empty group enables the new condition', () async {
    final result = await controller.pinFilters(request(name: 'Images', description: 'now'));

    expect(result.pinned, 1);
    final rule = controller.gallery.rules.single;
    expect(rule.kind, VisibleRangeRuleKind.restriction);
    expect(rule.label, 'Images');
    expect(rule.description, 'now');
    expect(rule.active, isTrue);
    expect(rule.filters, {image});
    expect(controller.galleryFilter, image);
  });

  test('an album becomes a source, the rest becomes a restriction', () async {
    await controller.pinFilters(request(filters: {albumA, favourite}));

    final source = controller.gallery.rulesOf(VisibleRangeRuleKind.source).single;
    final restriction = controller.gallery.rulesOf(VisibleRangeRuleKind.restriction).single;
    expect(source.filters, {albumA});
    expect(restriction.filters, {favourite});
    expect(controller.galleryFilter, isNotNull);
  });

  test('a second pin into a non-empty group is parked and keeps its state on re-pin', () async {
    await controller.pinFilters(request(filters: {image}));
    await controller.pinFilters(request(filters: {video}, name: 'Videos'));

    final videos = controller.gallery.rulesOf(VisibleRangeRuleKind.restriction).firstWhere((rule) => rule.filters.contains(video));
    expect(videos.active, isFalse);

    await controller.pinFilters(request(filters: {video}, name: 'Videos again'));
    final updated = controller.gallery.ruleById(videos.id)!;
    expect(updated.active, isFalse);
    expect(updated.label, 'Videos again');
  });

  test('the injection mode can force enabling or parking', () async {
    await controller.pinFilters(request(filters: {image}, injection: VisibleRangeInjectionMode.park));
    expect(controller.gallery.rules.single.active, isFalse);

    await controller.pinFilters(request(filters: {video}, injection: VisibleRangeInjectionMode.enable));
    final videos = controller.gallery.rules.firstWhere((rule) => rule.filters.contains(video));
    expect(videos.active, isTrue);
  });

  test('replace mode drops the conditions already in the group', () async {
    await controller.pinFilters(request(filters: {image}));
    await controller.pinFilters(request(filters: {video}, writeMode: VisibleRangePinWriteMode.replace));

    expect(controller.gallery.rules.single.filters, {video});
    expect(controller.gallery.rules.single.active, isTrue);
  });

  test('the outside restriction target puts every filter in its own restriction', () async {
    final outsideRestriction = (await controller.loadPinTargets()).singleWhere((target) => target.isOutside && target.role == VisibleRangeRuleKind.restriction);
    await controller.pinFilters(request(filters: {albumA, favourite}, targets: {outsideRestriction.id}));

    final rules = controller.outside.rules;
    expect(rules, hasLength(2));
    expect(rules.every((rule) => rule.kind == VisibleRangeRuleKind.restriction), isTrue);
    expect(rules.every((rule) => rule.active), isTrue);
    expect(controller.galleryFilter, isNotNull);
  });

  test('the outside supplement target puts every filter in its own supplement', () async {
    final outsideSupplement = (await controller.loadPinTargets()).singleWhere((target) => target.isOutside && target.role == VisibleRangeRuleKind.supplement);
    await controller.pinFilters(request(filters: {albumA, favourite}, targets: {outsideSupplement.id}));

    final rules = controller.outside.rules;
    expect(rules, hasLength(2));
    expect(rules.every((rule) => rule.kind == VisibleRangeRuleKind.supplement), isTrue);
  });

  test('a forced role overrides the automatic split', () async {
    await controller.pinFilters(request(filters: {albumA, favourite}, forcedRole: VisibleRangeRuleKind.source));
    expect(controller.gallery.rulesOf(VisibleRangeRuleKind.source).single.filters, {albumA, favourite});
    expect(controller.gallery.rulesOf(VisibleRangeRuleKind.restriction), isEmpty);
  });

  test('unknown target ids are skipped', () async {
    final result = await controller.pinFilters(request(targets: {controller.currentGalleryGroupId, 'wallpaper.1'}));
    expect(result.pinned, 1);
    expect(result.skipped, 1);
    expect(controller.gallery.rules, hasLength(1));
  });

  test('a locked gallery is skipped instead of failing the request', () async {
    await controller.lock(permissions: VisibleRangePermissions.readOnly);

    final result = await controller.pinFilters(request());
    expect(result.pinned, 0);
    expect(result.skipped, 1);
    expect(controller.gallery.rules, isEmpty);
    expect((await controller.loadPinTargets()).every((target) => target.locked), isTrue);
  });

  test('pinned conditions survive a restart', () async {
    await controller.pinFilters(request(name: 'Kept', description: 'keep me', filters: {albumA, favourite}));

    final restarted = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const []);
    await restarted.init();

    expect(restarted.gallery.rulesOf(VisibleRangeRuleKind.source).single.label, isEmpty);
    expect(restarted.gallery.rulesOf(VisibleRangeRuleKind.restriction).single.description, 'keep me');
  });

  test('an empty request is a no-op', () async {
    final result = await controller.pinFilters(const VisibleRangePinRequest(filters: {}, name: '', description: '', targetIds: {}));
    expect(result.pinned, 0);
    expect(result.skipped, 0);
    expect(controller.gallery.rules, isEmpty);
  });
}
