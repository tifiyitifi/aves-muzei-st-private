import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// The gate must select the same entries through SQL as the in-memory test, and
/// the summary exclusion must agree with the browsing scope.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
  });

  tearDown(() async {
    VisibleRangeGate.debugController = null;
    VisibleRangeGate.overlay = null;
    await db.close();
  });

  AvesEntry entry(int id, {required String directory, String mime = MimeTypes.jpeg}) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$directory/$id.${mime == MimeTypes.mp4 ? 'mp4' : 'jpg'}',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: mime,
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  Future<Set<int>> selectedIds(CollectionFilter filter) async {
    final predicate = predicateForFilters({filter});
    expect(predicate, isNotNull, reason: 'range must compile to SQL: $filter');
    final window = await service.loadEntryWindow(predicate: predicate!, sort: SortFactor.date, reverse: false, limit: 100, offset: 0);
    return window.map((entry) => entry.id).toSet();
  }

  VisibleRange range({required VisibleRangeOrder order}) => VisibleRange(
        id: VisibleRange.galleryRangeId,
        scope: VisibleRangeScope.gallery,
        ownerId: VisibleRange.galleryOwnerId,
        baseFilters: {PathFilter('/a')},
        rules: [
          VisibleRangeRule(id: 'r1', rangeId: 'gallery', kind: VisibleRangeRuleKind.restriction, position: 0, filters: {MimeFilter.image}),
          VisibleRangeRule(id: 'r2', rangeId: 'gallery', kind: VisibleRangeRuleKind.supplement, position: 1, filters: {MimeFilter.video}),
        ],
        order: order,
      );

  test('intersect-first matches the in-memory result', () async {
    final entries = [
      entry(1, directory: '/a'),
      entry(2, directory: '/a', mime: MimeTypes.mp4),
      entry(3, directory: '/b'),
    ];
    await service.insertEntries(entries.toSet());

    final resolved = range(order: VisibleRangeOrder.intersectFirst).resolve()!;
    final expected = entries.where(resolved.test).map((entry) => entry.id).toSet();
    expect(expected, {1, 2});
    expect(await selectedIds(resolved), expected);
  });

  test('union-first matches the in-memory result', () async {
    final entries = [
      entry(1, directory: '/a'),
      entry(2, directory: '/a', mime: MimeTypes.mp4),
      entry(3, directory: '/b'),
    ];
    await service.insertEntries(entries.toSet());

    final resolved = range(order: VisibleRangeOrder.unionFirst).resolve()!;
    final expected = entries.where(resolved.test).map((entry) => entry.id).toSet();
    expect(expected, {1});
    expect(await selectedIds(resolved), expected);
  });

  test('the summary exclusion keeps only entries inside the range', () async {
    await service.insertEntries({
      entry(1, directory: '/a'),
      entry(2, directory: '/a', mime: MimeTypes.mp4),
      entry(3, directory: '/b'),
    });

    final resolved = range(order: VisibleRangeOrder.intersectFirst).resolve()!;
    final exclusion = buildSummaryExclusion(hidden: {resolved.reverse()}, lockedVaultDirs: const {});
    final rows = await service.loadAlbumSummaryRows(exclusion);
    expect(rows.map((row) => row.directory), ['/a']);
    // The /a video is a supplement, so it stays in range; the /b image is out.
    expect(rows.single.count, 2);
  });

  test('the gate applies and clears the range', () async {
    final controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const <VisibleRangePresetDefinition>[]);
    await controller.init();
    VisibleRangeGate.debugController = controller;

    expect(VisibleRangeGate.filter, isNull);
    expect(VisibleRangeGate.apply({MimeFilter.image}), {MimeFilter.image});
    expect(VisibleRangeGate.summaryExclusion, isNull);

    await controller.selectBase(presetId: '', name: 'a', filters: {PathFilter('/a')});
    expect(VisibleRangeGate.filter, isNotNull);
    expect(VisibleRangeGate.apply({MimeFilter.image}), {MimeFilter.image, VisibleRangeGate.filter!});
    expect(VisibleRangeGate.summaryExclusion, VisibleRangeGate.filter!.reverse());
  });

  test('the wallpaper overlay joins the gallery range and can suspend it', () async {
    final controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const <VisibleRangePresetDefinition>[]);
    await controller.init();
    VisibleRangeGate.debugController = controller;
    await controller.selectBase(presetId: '', name: 'a', filters: {PathFilter('/a')});

    final group = PathFilter('/b');
    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(groupFilter: group);
    final combined = VisibleRangeGate.filter;
    expect(combined, isA<SetAndFilter>());
    expect((combined as SetAndFilter).innerFilters, {PathFilter('/a'), group});

    // The gallery page has no overlay: the group never applies there.
    VisibleRangeGate.overlay = null;
    expect(VisibleRangeGate.filter, PathFilter('/a'));

    // The page can ignore the gallery range temporarily; the group still applies.
    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(groupFilter: group, gallerySuspended: true);
    expect(VisibleRangeGate.filter, group);

    // Group 0 contributes nothing, so only the gallery range remains.
    VisibleRangeGate.overlay = const VisibleRangeBrowsingOverlay();
    expect(VisibleRangeGate.filter, PathFilter('/a'));
  });

  test('the overlay notifies only when its value changes', () {
    var notifications = 0;
    void listener() => notifications++;
    VisibleRangeGate.overlayListenable.addListener(listener);
    addTearDown(() => VisibleRangeGate.overlayListenable.removeListener(listener));

    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(groupFilter: PathFilter('/b'));
    expect(notifications, 1);

    // The page re-publishes on every sync; an equal value must not invalidate
    // every browsing cache again.
    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(groupFilter: PathFilter('/b'));
    expect(notifications, 1);

    // The page-local suspension is part of the value.
    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(groupFilter: PathFilter('/b'), gallerySuspended: true);
    expect(notifications, 2);

    // Group 0 clears the scope, which is a change too.
    VisibleRangeGate.overlay = null;
    expect(notifications, 3);

    VisibleRangeGate.overlay = null;
    expect(notifications, 3);
  });

  test('leaving the wallpaper page keeps the group scope but restores the gallery range', () async {
    final controller = VisibleRangeController(injectedDatabase: db, presetLoader: () async => const <VisibleRangePresetDefinition>[]);
    await controller.init();
    VisibleRangeGate.debugController = controller;
    await controller.selectBase(presetId: '', name: 'a', filters: {PathFilter('/a')});

    final group = PathFilter('/b');
    // While the page is open the gallery range can be temporarily suspended.
    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(groupFilter: group, gallerySuspended: true);
    expect(VisibleRangeGate.filter, group);

    // Leaving publishes the group scope alone: the group stays, the temporary
    // suspension is restored.
    VisibleRangeGate.setWallpaperScope(group);
    final combined = VisibleRangeGate.filter;
    expect(combined, isA<SetAndFilter>());
    expect((combined as SetAndFilter).innerFilters, {PathFilter('/a'), group});

    // Selecting group 0 clears the scope, so browsing falls back to the gallery.
    VisibleRangeGate.setWallpaperScope(null);
    expect(VisibleRangeGate.filter, PathFilter('/a'));
  });
}
