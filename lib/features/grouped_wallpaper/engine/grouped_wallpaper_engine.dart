import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_entry_source.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_names.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_plan.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:flutter/painting.dart';

/// What one sync did, for the page to report.
enum GroupedWallpaperSyncResult {
  /// A photo was baked and is now on screen.
  baked,

  /// The group resolves to no image: the placeholder is on screen.
  empty,

  /// The group is locked, so its current frame was kept.
  locked,

  /// The grouped wallpaper is not the system wallpaper: nothing was written.
  notActive,

  /// Reading, querying, baking or writing failed: the placeholder is on screen.
  failed,
}

/// The grouped wallpaper's control plane.
///
/// It owns the only writes to `state.json` and `current.png`: the current group's
/// media set is resolved in Dart (Aves has the EXIF-aware decoders and the
/// database), baked to one PNG, then the native renderer is asked to reload.
/// There is no timer and no prefetch in this phase: a frame changes only when the
/// service starts or the user asks for a sync.
class GroupedWallpaperEngine {
  final GroupedWallpaperPlatform platform;
  final GroupedWallpaperBaker baker;
  final GroupedWallpaperPlanLoader planLoader;
  final GroupedWallpaperEntrySource entrySource;
  final GroupedWallpaperNameResolver nameResolver;
  final WallpaperEngineLink link;

  /// Clock, injectable so a test can assert the written `bakedAt`.
  final int Function() now;

  final Future<Size?> Function() _targetSize;

  GroupedWallpaperStateStore? _store;
  Future<GroupedWallpaperSyncResult>? _inFlight;

  new({
    required this.platform,
    GroupedWallpaperBaker? baker,
    GroupedWallpaperPlanLoader? planLoader,
    GroupedWallpaperEntrySource? entrySource,
    GroupedWallpaperNameResolver? nameResolver,
    WallpaperEngineLink? link,
    Future<Size?> Function()? targetSize,
    int Function()? now,
  })  : baker = baker ?? GroupedWallpaperBaker(),
        planLoader = planLoader ?? SavedGroupedWallpaperPlanLoader(),
        entrySource = entrySource ?? GroupedWallpaperDbEntrySource(),
        nameResolver = nameResolver ?? resolveGroupedWallpaperName,
        link = link ?? wallpaperEngineLink,
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _targetSize = targetSize ?? platform.wallpaperSize;

  bool get isAttached => _store != null;

  /// Wires the engine to the platform channel and to the page's sync entry.
  ///
  /// Inert on a host without the service (desktop, tests): the page then keeps
  /// its sync entry greyed out instead of failing.
  Future<void> attach() async {
    if (_store != null) return;
    final root = await platform.stateRoot();
    if (root == null) return;
    final store = GroupedWallpaperStateStore(Directory(root));
    await store.ensureLayout();
    _store = store;
    // The service asks for a frame when it starts: that is what gives the
    // wallpaper its first photo, with no background worker involved.
    platform.setSyncRequestHandler(onSyncRequested: () => unawaited(syncNow()));
    link.attach(syncNow: syncNow, isActive: platform.isActive);
    await link.refreshActive();
  }

  void detach() {
    platform.setSyncRequestHandler();
    link.detach();
    _store = null;
  }

  Future<bool> isActive() => platform.isActive();

  Future<bool> openChooser() => platform.openChooser();

  /// Re-bakes the saved current group and applies it now.
  ///
  /// Concurrent callers share one run: the service's start request and the page's
  /// button must not bake two frames into the same file.
  Future<GroupedWallpaperSyncResult> syncNow() {
    return _inFlight ??= _sync().whenComplete(() => _inFlight = null);
  }

  Future<GroupedWallpaperSyncResult> _sync() async {
    final store = _store;
    if (store == null) return GroupedWallpaperSyncResult.notActive;
    if (!await platform.isActive()) {
      await link.refreshActive();
      return GroupedWallpaperSyncResult.notActive;
    }
    await link.refreshActive();

    GroupedWallpaperPlan? plan;
    GroupedWallpaperState? previous;
    try {
      plan = await planLoader.load();
      previous = await store.readState();
      if (plan.locked) {
        await _recordLocked(store, plan, previous);
        return GroupedWallpaperSyncResult.locked;
      }
      final window = await entrySource.load(plan.range, limit: GroupedWallpaperDbEntrySource.scanLimit);
      final entry = selectGroupedWallpaperEntry(window.entries, previousEntryId: previous?.entryId);
      if (entry == null) {
        await store.clearPhoto();
        await store.writeState(_buildState(plan: plan, previous: previous, status: GroupedWallpaperStatus.emptyGroup, count: window.count));
        await platform.reload();
        return GroupedWallpaperSyncResult.empty;
      }
      final bake = await baker.bake(entry: entry, targetSize: await _resolveTargetSize());
      await store.writePhoto(bake.png);
      await store.writeState(
        _buildState(
          plan: plan,
          previous: previous,
          status: GroupedWallpaperStatus.ready,
          count: window.count,
          entry: entry,
          photo: GroupedWallpaperState.photoFileName,
          size: bake.size,
        ),
      );
      await platform.reload();
      return GroupedWallpaperSyncResult.baked;
    } catch (error, stack) {
      groupedWallpaperLog.e('sync failed', error, stack);
      await _recordFailure(store, plan, previous);
      return GroupedWallpaperSyncResult.failed;
    }
  }

  /// Freezes the frame on screen: a locked group is not re-baked, so the state
  /// keeps its photo and only records the lock for the notification.
  Future<void> _recordLocked(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, GroupedWallpaperState? previous) async {
    if (previous?.status == GroupedWallpaperStatus.locked && previous?.groupId == plan.group.id) return;
    final state = previous != null
        ? previous.copyWith(status: GroupedWallpaperStatus.locked)
        : _buildState(plan: plan, previous: previous, status: GroupedWallpaperStatus.locked, count: 0);
    await store.writeState(state);
  }

  /// A failed sync leaves the placeholder, never the previous photo: a stale
  /// image would claim the wallpaper is still following the group.
  Future<void> _recordFailure(GroupedWallpaperStateStore store, GroupedWallpaperPlan? plan, GroupedWallpaperState? previous) async {
    try {
      await store.clearPhoto();
      final state = plan != null
          ? _buildState(plan: plan, previous: previous, status: GroupedWallpaperStatus.unavailable, count: 0)
          : GroupedWallpaperState(
              generation: (previous?.generation ?? 0) + 1,
              status: GroupedWallpaperStatus.unavailable,
              groupId: previous?.groupId ?? '',
              groupNumber: previous?.groupNumber ?? 0,
              groupName: previous?.groupName ?? '',
              bakedAt: now(),
            );
      await store.writeState(state);
      await platform.reload();
    } catch (error, stack) {
      // The renderer still has no state file to read, which already shows the
      // placeholder: a second failure must not escape either.
      groupedWallpaperLog.e('failed to record the sync failure', error, stack);
    }
  }

  GroupedWallpaperState _buildState({
    required GroupedWallpaperPlan plan,
    required GroupedWallpaperState? previous,
    required GroupedWallpaperStatus status,
    required int count,
    AvesEntry? entry,
    String photo = '',
    Size? size,
  }) =>
      GroupedWallpaperState(
        generation: (previous?.generation ?? 0) + 1,
        status: status,
        groupId: plan.group.id,
        groupNumber: plan.group.number,
        groupName: _resolveName(plan.group),
        count: count,
        entryId: entry?.id,
        entryTitle: entry?.bestTitle ?? '',
        photo: photo,
        width: size?.width.round() ?? 0,
        height: size?.height.round() ?? 0,
        bakedAt: now(),
      );

  String _resolveName(WallpaperGroup group) {
    try {
      return nameResolver(group);
    } catch (error, stack) {
      // A missing localization must not cost the user their wallpaper.
      groupedWallpaperLog.w('failed to resolve the group name', error, stack);
      return group.name;
    }
  }

  Future<Size> _resolveTargetSize() async {
    final requested = await _targetSize();
    if (requested != null && requested.width > 0 && requested.height > 0) return requested;
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    final size = view == null ? null : view.physicalSize / view.devicePixelRatio;
    if (size != null && size.width > 0 && size.height > 0) return size;
    return const Size(1080, 1920);
  }
}

/// The app-wide engine.
///
/// It is attached at startup so the service can ask for a frame even when the
/// wallpaper page was never opened.
final groupedWallpaperEngine = GroupedWallpaperEngine(platform: GroupedWallpaperBridge.instance);
