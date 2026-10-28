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

/// The grouped wallpaper's control plane.
///
/// It owns the only writes to `state.json` and `current.png`: the current group's
/// media set is resolved in Dart (Aves has the EXIF-aware decoders and the
/// database), baked to one PNG, then the native renderer is asked to reload.
///
/// Two entry points share the same pipeline:
/// - [prepare] keeps a frame ready for the saved group and never requires the
///   service to be the system wallpaper yet, because the system picker can take
///   a moment to hand it over;
/// - [syncNow] is the user asking for the next photo, and only applies while the
///   service really is the system wallpaper.
///
/// There is no timer and no prefetch in this phase: a frame changes when the app
/// prepares it after a save or a group switch, when the service starts, or when
/// the user asks for a sync.
class GroupedWallpaperEngine implements WallpaperEngineConnection {
  final GroupedWallpaperPlatform platform;
  final GroupedWallpaperBaker baker;
  final GroupedWallpaperPlanStore planStore;
  final GroupedWallpaperEntrySource entrySource;
  final GroupedWallpaperNameResolver nameResolver;
  final WallpaperEngineLink link;

  /// Clock, injectable so a test can assert the written `bakedAt`.
  final int Function() now;

  final Future<Size?> Function() _targetSize;

  GroupedWallpaperStateStore? _store;

  /// Runs one pipeline at a time: the service's start request and the page's
  /// button must never bake two frames into the same file.
  Future<void> _queue = Future.value();

  new({
    required this.platform,
    GroupedWallpaperBaker? baker,
    GroupedWallpaperPlanStore? planStore,
    GroupedWallpaperEntrySource? entrySource,
    GroupedWallpaperNameResolver? nameResolver,
    WallpaperEngineLink? link,
    Future<Size?> Function()? targetSize,
    int Function()? now,
  })  : baker = baker ?? GroupedWallpaperBaker(),
        planStore = planStore ?? SavedGroupedWallpaperPlanStore(),
        entrySource = entrySource ?? GroupedWallpaperDbEntrySource(),
        nameResolver = nameResolver ?? resolveGroupedWallpaperName,
        link = link ?? wallpaperEngineLink,
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _targetSize = targetSize ?? platform.wallpaperSize;

  bool get isAttached => _store != null;

  /// Wires the engine to the platform channel and to the page's entries.
  ///
  /// Inert on a host without the service (desktop, tests): the page then keeps
  /// its entries greyed out instead of failing.
  Future<void> attach() async {
    if (_store != null) return;
    final root = await platform.stateRoot();
    if (root == null) return;
    final store = GroupedWallpaperStateStore(Directory(root));
    await store.ensureLayout();
    _store = store;
    // The service asks for a frame when it starts, and that moment is also the
    // activation: the system picker may not have committed the switch yet, so
    // the request must not be filtered by `isActive`.
    platform.setSyncRequestHandler(onSyncRequested: () => unawaited(prepare(activation: true)));
    link.attach(this);
    await link.refreshActive();
    await link.refreshDisabled();
  }

  void detach() {
    platform.setSyncRequestHandler();
    link.detach();
    _store = null;
  }

  @override
  Future<bool> isActive() => platform.isActive();

  @override
  Future<bool> isDisabled() async => (await planStore.load()).disabled;

  @override
  Future<bool> openChooser() => platform.openChooser();

  /// The state the renderer is showing, or null when nothing was ever baked.
  @override
  Future<GroupedWallpaperState?> readState() async => await _store?.readState();

  /// Records the explicit off/on switch without touching the current group.
  @override
  Future<void> setDisabled(bool disabled) async {
    await planStore.setDisabled(disabled);
    await link.refreshDisabled();
  }

  /// Keeps a frame ready for the saved group, whether or not the grouped service
  /// is the system wallpaper yet.
  ///
  /// [activation] is the service telling us it was just created. Only then does
  /// "no group is current" fall back to the first enabled group: a restart of an
  /// install the user turned off must stay off.
  @override
  Future<GroupedWallpaperSyncResult> prepare({bool activation = false}) {
    return _enqueue(() => _run(advance: false, requireActive: false, activation: activation));
  }

  /// Re-bakes the saved current group and applies it now.
  ///
  /// Only meaningful while the grouped wallpaper is the system wallpaper: writing
  /// a frame the renderer is not showing would claim a change that never happened.
  @override
  Future<GroupedWallpaperSyncResult> syncNow() {
    return _enqueue(() => _run(advance: true, requireActive: true, activation: false));
  }

  Future<GroupedWallpaperSyncResult> _enqueue(Future<GroupedWallpaperSyncResult> Function() body) {
    final result = _queue.then((_) => body());
    // The queue must survive a failed run, or every later call would be skipped.
    _queue = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<GroupedWallpaperSyncResult> _run({required bool advance, required bool requireActive, required bool activation}) async {
    final store = _store;
    if (store == null) return GroupedWallpaperSyncResult.notActive;
    if (requireActive && !await platform.isActive()) {
      await link.refreshActive();
      return GroupedWallpaperSyncResult.notActive;
    }
    await link.refreshActive();

    GroupedWallpaperPlan? plan;
    GroupedWallpaperState? previous;
    try {
      plan = await planStore.load();
      previous = await store.readState();
      // Turning the wallpaper on with no group selected must not leave the
      // placeholder: land on the first enabled group instead.
      if (activation && plan.isNone && !plan.disabled) {
        plan = await planStore.adoptFirstEnabledGroup();
      }
      if (plan.disabled) {
        await _recordDisabled(store, previous);
        return GroupedWallpaperSyncResult.disabled;
      }
      if (plan.isNone) {
        if (_wasPlayingAGroup(previous)) {
          // The playing group was deleted or disabled: freeze its last frame and
          // turn the feature off rather than silently switching content.
          await planStore.setDisabled(true);
          await _recordDisabled(store, previous);
          return GroupedWallpaperSyncResult.disabled;
        }
        // No group was ever played: leave the frame alone until the wallpaper is
        // activated, which is what adopts the first group.
        return GroupedWallpaperSyncResult.unchanged;
      }
      if (plan.locked) {
        await _recordLocked(store, plan, previous);
        return GroupedWallpaperSyncResult.locked;
      }
      if (!advance && await _isFresh(store, plan, previous)) {
        return GroupedWallpaperSyncResult.unchanged;
      }
      final window = await entrySource.load(plan.range, limit: GroupedWallpaperDbEntrySource.scanLimit);
      final entry = selectGroupedWallpaperEntry(window.entries, previousEntryId: advance ? previous?.entryId : null);
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

  /// Whether [previous] is a frame of a real group, i.e. the wallpaper was
  /// following something that has since disappeared.
  static bool _wasPlayingAGroup(GroupedWallpaperState? previous) => previous != null && previous.hasPhoto && previous.groupId.isNotEmpty;

  /// Whether [previous] already shows [plan]'s group with nothing newer to bake.
  ///
  /// Saving a draft or switching the group bumps `updatedAt`, so a changed group
  /// always re-bakes; an unchanged one keeps the photo it already shows instead
  /// of cycling through another image on every app start.
  Future<bool> _isFresh(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, GroupedWallpaperState? previous) async {
    if (previous == null || previous.status != GroupedWallpaperStatus.ready || !previous.hasPhoto) return false;
    if (previous.groupId != plan.group.id) return false;
    if (previous.bakedAt < plan.group.updatedAt) return false;
    if (previous.bakedAt < (plan.range?.updatedAt ?? 0)) return false;
    // The file can be gone while the state still points at it (cache cleanup,
    // manual wipe): a frame that is not on disk is not fresh.
    return await store.photoFile.exists();
  }

  /// Freezes the frame on screen: a locked group is not re-baked, so the state
  /// keeps its photo and only records the lock for the notification.
  Future<void> _recordLocked(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, GroupedWallpaperState? previous) async {
    if (previous?.status == GroupedWallpaperStatus.locked && previous?.groupId == plan.group.id) return;
    final state = previous != null
        ? previous.copyWith(generation: previous.generation + 1, status: GroupedWallpaperStatus.locked)
        : _buildState(plan: plan, previous: previous, status: GroupedWallpaperStatus.locked, count: 0);
    await store.writeState(state);
  }

  /// Records that the grouped wallpaper is off without touching the frame.
  ///
  /// Disabling never changes what the system is showing: the photo stays, and
  /// only the status tells the page and the notification that the group is no
  /// longer being followed.
  Future<void> _recordDisabled(GroupedWallpaperStateStore store, GroupedWallpaperState? previous) async {
    if (previous == null || previous.status == GroupedWallpaperStatus.disabled) return;
    await store.writeState(previous.copyWith(generation: previous.generation + 1, status: GroupedWallpaperStatus.disabled));
    await platform.reload();
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
