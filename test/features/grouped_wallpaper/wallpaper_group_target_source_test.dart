import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_target_source.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Pinning addresses a group's condition pool, one target per group, and stores
/// the conditions unmarked.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupController groups;
  late VisibleRangeController ranges;
  late WallpaperGroupTargetSource source;

  List<WallpaperGroupDefinition> bundle() => const [
        WallpaperGroupDefinition(id: 'a', nameKey: 'wallpaperGroupDefaultAll', current: true),
        WallpaperGroupDefinition(id: 'b', nameKey: 'wallpaperGroupDefaultDcim'),
      ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    groups = WallpaperGroupController(injectedDatabase: db, defaultLoader: () async => bundle());
    await groups.init();
    ranges = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const []);
    await ranges.init();
    source = WallpaperGroupTargetSource(groups);
    ranges.targetSource = source;
  });

  tearDown(() => db.close());

  VisibleRangePinRequest request({
    Set<CollectionFilter> filters = const {},
    Set<VisibleRangeCandidateKind> kinds = const {VisibleRangeCandidateKind.restriction},
    Set<String>? targets,
    String name = 'Pinned',
  }) {
    return VisibleRangePinRequest(
      filters: filters.isEmpty ? {MimeFilter.image} : filters,
      name: name,
      description: 'note',
      kinds: kinds,
      targetRangeIds: targets ?? {wallpaperGroupRangeId('a')},
    );
  }

  test('a split group is still one pin target', () async {
    await groups.setSeparateLockRange('a', true);

    final targets = await ranges.loadPinTargets();
    final groupTargets = targets.where((target) => !target.isGallery).toList();

    expect(groupTargets, hasLength(2));
    expect(groupTargets.map((target) => target.rangeId), [wallpaperGroupRangeId('a'), wallpaperGroupRangeId('b')]);
    expect(groupTargets.map((target) => target.rangeId), isNot(contains(wallpaperGroupLockRangeId('a'))));
  });

  test('a pinned restriction lands in the pool unmarked and does not reach a surface', () async {
    final result = await ranges.pinFilters(request());

    expect(result.pinned, 1);
    final pool = await groups.groupPool('a');
    final rule = pool.rules.single;
    expect(rule.filters, {MimeFilter.image});
    expect(rule.surfaces, 0);
    expect(pool.baseFilters, isEmpty);
    // Neither projection uses it until the user marks a surface.
    expect((await groups.groupRange('a')).rules, isEmpty);
    expect((await groups.groupRange('a', surface: WallpaperSurface.lock)).rules, isEmpty);

    // Marking Home is what activates the shared condition for that surface only.
    await groups.saveGroupPool(pool.copyWith(rules: [rule.copyWith(surfaces: WallpaperConditionSurfaces.home)]));
    expect((await groups.groupRange('a')).rules.single.filters, {MimeFilter.image});
    expect((await groups.groupRange('a', surface: WallpaperSurface.lock)).rules, isEmpty);
  });

  test('re-pinning updates the shared condition instead of adding one per surface', () async {
    await ranges.pinFilters(request());
    final first = (await groups.groupPool('a')).rules.single;
    await groups.saveGroupPool((await groups.groupPool('a')).copyWith(rules: [first.copyWith(surfaces: WallpaperConditionSurfaces.lock)]));

    await ranges.pinFilters(request(name: 'Renamed'));

    final pool = await groups.groupPool('a');
    expect(pool.rules, hasLength(1));
    expect(pool.rules.single.id, first.id);
    expect(pool.rules.single.label, 'Renamed');
    expect(pool.rules.single.surfaces, WallpaperConditionSurfaces.lock);
  });

  test('a pinned base keeps the marks the pool already had', () async {
    // An unmarked base stays unmarked: pinning never activates a surface.
    await ranges.pinFilters(request(kinds: {VisibleRangeCandidateKind.base}, name: 'Base one'));
    var pool = await groups.groupPool('a');
    expect(pool.baseFilters, {MimeFilter.image});
    expect(pool.baseSurfaces, 0);

    // Once Home uses a base, re-pinning its filters keeps that mark.
    await groups.saveGroupPool(pool.copyWith(baseSurfaces: WallpaperConditionSurfaces.home));
    await ranges.pinFilters(request(filters: {PathFilter('/pictures')}, kinds: {VisibleRangeCandidateKind.base}, name: 'Base two'));

    pool = await groups.groupPool('a');
    expect(pool.baseName, 'Base two');
    expect(pool.baseFilters, {PathFilter('/pictures')});
    expect(pool.baseSurfaces, WallpaperConditionSurfaces.home);
  });

  test('a historical lock range id resolves and saves as the pool', () async {
    await groups.setSeparateLockRange('a', true);
    final pool = await groups.groupPool('a');

    expect((await source.loadRange(wallpaperGroupLockRangeId('a')))?.id, pool.id);

    // A writer that still builds a lock projection cannot create a second row.
    final legacy = VisibleRange(
      id: wallpaperGroupLockRangeId('a'),
      scope: VisibleRangeScope.wallpaper,
      ownerId: wallpaperGroupLockOwnerId('a'),
      baseName: 'Legacy base',
    );
    await source.saveRange(legacy);

    final saved = await groups.groupPool('a');
    expect(saved.id, pool.id);
    expect(saved.ownerId, 'a');
    expect(saved.baseName, 'Legacy base');
    expect(saved.rules, isEmpty);
  });

  test('a write-back addressed through the lock id still names its group', () async {
    await groups.setSeparateLockRange('a', true);
    await ranges.pinFilters(request());

    final rule = (await groups.groupPool('a')).rules.single;
    await ranges.markAppliedTargets(rangeId: wallpaperGroupLockRangeId('a'), candidates: [VisibleRangeCandidate.fromRule(rule)]);

    final targets = await ranges.loadAppliedTargets();
    expect(targets, hasLength(1));
    expect(targets.single.isGallery, isFalse);
    expect(targets.single.number, 1);
    expect(targets.single.ownerName, '@wallpaperGroupDefaultAll');
    expect(targets.single.label, 'Pinned');
  });
}
