import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_engine.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_entry_source.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_plan.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state_store.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperEngine`: which frame a sync bakes, what it writes, and how
/// every failure degrades to the placeholder instead of a stale image.
void main() {
  const dcimGroup = WallpaperGroup(id: 'group.1', number: 1, name: '@wallpaperGroupDefaultDcim', current: true);
  const plan = GroupedWallpaperPlan(group: dcimGroup);

  late Directory dir;
  late _FakePlatform platform;
  late _FakeBaker baker;
  late _FakePlanLoader planLoader;
  late _FakeEntrySource entrySource;
  late GroupedWallpaperStateStore store;
  late WallpaperEngineLink link;
  late GroupedWallpaperEngine engine;

  AvesEntry entry(int id) => AvesEntry(
        id: id,
        uri: 'content://media/$id',
        path: null,
        contentId: id,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 300,
        height: 100,
        sourceRotationDegrees: 0,
        sizeBytes: 1,
        sourceTitle: 'IMG_$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aves_grouped_engine_');
    platform = _FakePlatform(dir.path);
    baker = _FakeBaker();
    planLoader = _FakePlanLoader(plan);
    entrySource = _FakeEntrySource();
    store = GroupedWallpaperStateStore(dir);
    link = WallpaperEngineLink();
    engine = GroupedWallpaperEngine(
      platform: platform,
      baker: baker,
      planLoader: planLoader,
      entrySource: entrySource,
      nameResolver: (group) => 'DCIM',
      link: link,
      targetSize: () async => const Size(100, 200),
      now: () => 1234,
    );
    await engine.attach();
  });

  tearDown(() async {
    engine.detach();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('attach wires the platform, the link and the service request', () {
    expect(engine.isAttached, isTrue);
    expect(link.isAttached, isTrue);
    expect(link.isActive, isTrue);
    expect(platform.syncHandler, isNotNull);
  });

  test('a host without the service stays inert', () async {
    final hostless = _FakePlatform(null);
    final hostlessLink = WallpaperEngineLink();
    final hostlessEngine = GroupedWallpaperEngine(platform: hostless, link: hostlessLink);

    await hostlessEngine.attach();

    expect(hostlessEngine.isAttached, isFalse);
    expect(hostlessLink.isAttached, isFalse);
    expect(await hostlessEngine.syncNow(), GroupedWallpaperSyncResult.notActive);
  });

  test('does nothing while the grouped wallpaper is not the system wallpaper', () async {
    platform.active = false;

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.notActive);
    expect(await store.stateFile.exists(), isFalse);
    expect(baker.bakeCount, 0);
    expect(link.isActive, isFalse);
  });

  test('bakes the newest image and records the group, entry and size', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 12, entries: [entry(2), entry(1)]);

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.baked);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.ready);
    expect(state.generation, 1);
    expect(state.groupId, dcimGroup.id);
    expect(state.groupNumber, 1);
    expect(state.groupName, 'DCIM');
    expect(state.count, 12);
    expect(state.entryId, 2);
    expect(state.entryTitle, 'IMG_2');
    expect(state.photo, GroupedWallpaperState.photoFileName);
    expect(state.width, 100);
    expect(state.height, 200);
    expect(state.bakedAt, 1234);
    expect(await store.photoFile.exists(), isTrue);
    expect(platform.reloadCount, 1);
    expect(baker.lastTarget, const Size(100, 200));
    expect(entrySource.lastRange, isNull);
  });

  test('a second sync shows another image instead of the same one', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 12, entries: [entry(2), entry(1)]);
    await engine.syncNow();

    await engine.syncNow();

    expect(baker.lastEntry?.id, 1);
    final state = (await store.readState())!;
    expect(state.entryId, 1);
    expect(state.generation, 2);
  });

  test('a group with a single image keeps showing it', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 1, entries: [entry(5)]);
    await engine.syncNow();

    await engine.syncNow();

    expect(baker.lastEntry?.id, 5);
    expect((await store.readState())!.entryId, 5);
  });

  test('an empty group clears the photo and records the empty state', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 1, entries: [entry(2)]);
    await engine.syncNow();
    expect(await store.photoFile.exists(), isTrue);

    entrySource.window = GroupedWallpaperEntryWindow.empty;
    expect(await engine.syncNow(), GroupedWallpaperSyncResult.empty);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.emptyGroup);
    expect(state.count, 0);
    expect(state.hasPhoto, isFalse);
    expect(await store.photoFile.exists(), isFalse);
    expect(platform.reloadCount, 2);
  });

  test('a locked group keeps its frame and bakes nothing', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 12, entries: [entry(2), entry(1)]);
    await engine.syncNow();
    final frozen = (await store.readState())!;
    final bakes = baker.bakeCount;
    final reloads = platform.reloadCount;

    planLoader.plan = GroupedWallpaperPlan(
      group: dcimGroup,
      range: VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id, locked: true),
    );
    expect(await engine.syncNow(), GroupedWallpaperSyncResult.locked);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.locked);
    expect(state.entryId, frozen.entryId);
    expect(state.photo, frozen.photo);
    expect(state.hasPhoto, isTrue);
    expect(baker.bakeCount, bakes);
    expect(platform.reloadCount, reloads);
    expect(await store.photoFile.exists(), isTrue);
  });

  test('a locked group with no frame yet writes a placeholder state', () async {
    planLoader.plan = GroupedWallpaperPlan(
      group: dcimGroup,
      range: VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id, locked: true),
    );

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.locked);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.locked);
    expect(state.hasPhoto, isFalse);
    expect(state.groupId, dcimGroup.id);
    expect(baker.bakeCount, 0);
  });

  test('a bake failure clears the photo and shows the placeholder', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 1, entries: [entry(2)]);
    await engine.syncNow();
    baker.error = const GroupedWallpaperBakeException('decode failed');

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.failed);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.unavailable);
    expect(state.hasPhoto, isFalse);
    expect(await store.photoFile.exists(), isFalse);
    expect(state.groupId, dcimGroup.id);
    expect(platform.reloadCount, 2);
  });

  test('a plan read failure still leaves the placeholder, not the old frame', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 1, entries: [entry(2)]);
    await engine.syncNow();
    planLoader.error = StateError('database is gone');

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.failed);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.unavailable);
    expect(await store.photoFile.exists(), isFalse);
  });

  test('concurrent syncs share one bake', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 2, entries: [entry(2), entry(1)]);

    final results = await Future.wait([engine.syncNow(), engine.syncNow()]);

    expect(results, [GroupedWallpaperSyncResult.baked, GroupedWallpaperSyncResult.baked]);
    expect(baker.bakeCount, 1);
    expect(platform.reloadCount, 1);
  });

  test('the service request runs a sync', () async {
    entrySource.window = GroupedWallpaperEntryWindow(count: 1, entries: [entry(3)]);
    final reloaded = Completer<void>();
    platform.onReload = () {
      if (!reloaded.isCompleted) reloaded.complete();
    };

    platform.syncHandler!.call();
    await reloaded.future;

    expect(baker.lastEntry?.id, 3);
    expect((await store.readState())!.entryId, 3);
  });

  test('the group range is what the media set is resolved from', () async {
    final range = VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id);
    planLoader.plan = GroupedWallpaperPlan(group: dcimGroup, range: range);
    entrySource.window = GroupedWallpaperEntryWindow(count: 1, entries: [entry(4)]);

    await engine.syncNow();

    expect(entrySource.lastRange, range);
  });

  group('selectGroupedWallpaperEntry', () {
    test('skips the entry already on screen', () {
      expect(selectGroupedWallpaperEntry([entry(2), entry(1)], previousEntryId: 2)?.id, 1);
    });

    test('falls back to the previous entry when it is the only one', () {
      expect(selectGroupedWallpaperEntry([entry(2)], previousEntryId: 2)?.id, 2);
    });

    test('skips entries whose file disappeared', () {
      final missing = entry(3).copyWith(path: '/gone/3.jpg');
      expect(selectGroupedWallpaperEntry([missing, entry(1)])?.id, 1);
    });

    test('reports nothing when every entry is missing', () {
      final missing = entry(3).copyWith(path: '/gone/3.jpg');
      expect(selectGroupedWallpaperEntry([missing]), isNull);
    });
  });
}

class _FakePlatform implements GroupedWallpaperPlatform {
  final String? root;
  bool active = true;
  int reloadCount = 0;
  bool chooserOpened = false;
  VoidCallback? syncHandler;
  VoidCallback? onReload;

  new(this.root);

  @override
  Future<bool> isActive() async => active;

  @override
  Future<String?> stateRoot() async => root;

  @override
  Future<Size?> wallpaperSize() async => const Size(100, 200);

  @override
  Future<void> reload() async {
    reloadCount++;
    onReload?.call();
  }

  @override
  Future<bool> openChooser() async {
    chooserOpened = true;
    return true;
  }

  @override
  void setSyncRequestHandler({VoidCallback? onSyncRequested}) {
    syncHandler = onSyncRequested;
  }
}

class _FakeBaker extends GroupedWallpaperBaker {
  int bakeCount = 0;
  AvesEntry? lastEntry;
  Size? lastTarget;
  Object? error;

  @override
  Future<GroupedWallpaperBake> bake({required AvesEntry entry, required Size targetSize}) async {
    bakeCount++;
    lastEntry = entry;
    lastTarget = targetSize;
    final failure = error;
    if (failure != null) throw failure;
    return GroupedWallpaperBake(png: Uint8List.fromList([1, 2, 3]), size: targetSize);
  }
}

class _FakePlanLoader implements GroupedWallpaperPlanLoader {
  GroupedWallpaperPlan plan;
  Object? error;

  new(this.plan);

  @override
  Future<GroupedWallpaperPlan> load() async {
    final failure = error;
    if (failure != null) throw failure;
    return plan;
  }
}

class _FakeEntrySource implements GroupedWallpaperEntrySource {
  GroupedWallpaperEntryWindow window = GroupedWallpaperEntryWindow.empty;
  VisibleRange? lastRange;

  @override
  Future<GroupedWallpaperEntryWindow> load(VisibleRange? range, {required int limit}) async {
    lastRange = range;
    return window;
  }
}
