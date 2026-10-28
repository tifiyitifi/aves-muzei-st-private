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
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:flutter/painting.dart';

/// The grouped wallpaper's control plane.
///
/// It owns the only writes to `state.json` and the slot photos: the current
/// group's media set is resolved in Dart (Aves has the EXIF-aware decoders and
/// the database), baked to cover-cropped PNGs, then the native renderer is asked
/// to reload.
///
/// Two entry points share the same pipeline:
/// - [prepare] keeps the queue ready for the saved group and never requires the
///   service to be the system wallpaper yet, because the system picker can take
///   a moment to hand it over;
/// - [syncNow] is the user asking for the next photo, and only applies while the
///   service really is the system wallpaper.
///
/// The queue is `current → next → next2`: the renderer promotes `next` on a
/// wallpaper tap without waiting for Flutter, records what it did in
/// `runtime.json`, and Dart bakes the slot it left behind. Two consecutive taps
/// therefore need no bake.
class GroupedWallpaperEngine implements WallpaperEngineConnection {
  /// How many photos are baked ahead of the one on screen.
  ///
  /// Two matches Muzei's default: the first two taps are instant, and the
  /// renderer buffers the rest until Dart catches up.
  static const int prefetchAhead = 2;

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

  /// Absolute path of the photo on screen, for the view page.
  @override
  Future<String?> currentPhotoPath() async {
    final state = await _store?.readState();
    final slot = state?.currentSlot;
    if (slot == null) return null;
    return _store?.slotPhotoOf(slot)?.path;
  }

  /// Records the explicit off/on switch without touching the current group.
  @override
  Future<void> setDisabled(bool disabled) async {
    await planStore.setDisabled(disabled);
    await link.refreshDisabled();
  }

  /// Keeps the queue ready for the saved group, whether or not the grouped
  /// service is the system wallpaper yet.
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

  /// One run driven by the background worker or an auto-advance interval.
  Future<GroupedWallpaperSyncResult> refill({required bool advance}) {
    return _enqueue(() => _run(advance: advance, requireActive: false, activation: false));
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

      // The renderer may have promoted a slot on its own; adopt it before
      // deciding what to bake, or the freed slot would never be refilled.
      final runtime = await store.readRuntime();
      final adopted = _adoptRuntime(previous, runtime);
      final promoted = !identical(adopted, previous);
      final stale = _isStale(plan, adopted);
      final (seed, advanced) = advance && !stale ? _promote(adopted) : (adopted, false);
      final window = await entrySource.load(plan.range, limit: GroupedWallpaperDbEntrySource.scanLimit);
      // A promoted slot must be recorded even when nothing is baked, so the
      // runtime stops matching and the next run starts from the new current.
      if (!advance && !stale && !promoted && await _isQueueReady(store, window, adopted)) {
        return GroupedWallpaperSyncResult.unchanged;
      }
      return await _bakeQueue(
        store,
        plan,
        window: window,
        seed: stale ? null : seed,
        exclude: stale ? const {} : {for (final slot in previous?.slots ?? const <GroupedWallpaperSlot>[]) slot.entryId},
        mustWrite: promoted || advanced,
      );
    } catch (error, stack) {
      groupedWallpaperLog.e('sync failed', error, stack);
      await _recordFailure(store, plan, previous);
      return GroupedWallpaperSyncResult.failed;
    }
  }

  /// Bakes every missing slot of the queue for [plan].
  ///
  /// [seed] is the queue to keep (current/next survive), or null to start over.
  /// [mustWrite] forces a state write even when nothing was baked, because the
  /// renderer already promoted a slot and its runtime must stop matching.
  Future<GroupedWallpaperSyncResult> _bakeQueue(
    GroupedWallpaperStateStore store,
    GroupedWallpaperPlan plan, {
    required GroupedWallpaperEntryWindow window,
    GroupedWallpaperState? seed,
    required Set<int> exclude,
    required bool mustWrite,
  }) async {
    final state = seed;
    var current = state?.current ?? -1;
    var next = state?.next ?? -1;
    var next2 = state?.next2 ?? -1;
    final slots = <GroupedWallpaperSlot>[
      for (final slot in state?.slots ?? const <GroupedWallpaperSlot>[])
        // A slot whose file disappeared is not part of the queue any more: it
        // must be re-baked, not kept as an empty frame.
        if ((slot.id == current || slot.id == next || slot.id == next2) && store.slotPhotoOf(slot) != null) slot,
    ];
    if (!slots.any((slot) => slot.id == current)) current = -1;
    if (!slots.any((slot) => slot.id == next)) next = -1;
    if (!slots.any((slot) => slot.id == next2)) next2 = -1;

    final skip = {...exclude, for (final slot in slots) slot.entryId};
    final picked = _pickEntries(window.entries, exclude: skip, count: prefetchAhead + 1);

    // A slot keeps its id while it stays in the queue, so the renderer can keep
    // the texture it already uploaded.
    final usedIds = {for (final slot in slots) slot.id};
    var pickIndex = 0;
    var bakedAny = false;
    Future<GroupedWallpaperSlot?> bakeInto(int? keepId) async {
      if (pickIndex >= picked.length) return null;
      final entry = picked[pickIndex++];
      final id = keepId != null && keepId >= 0 ? keepId : _nextSlotId(usedIds);
      usedIds.add(id);
      final bake = await baker.bake(entry: entry, targetSize: await _resolveTargetSize());
      final photo = await store.writeSlotPhoto(id, bake.png);
      bakedAny = true;
      return GroupedWallpaperSlot(
        id: id,
        entryId: entry.id,
        uri: entry.uri,
        title: entry.bestTitle ?? '',
        photo: photo,
        width: bake.size.width.round(),
        height: bake.size.height.round(),
      );
    }

    // `current` first: it is what the user sees, so it must never be the slot
    // left empty while the queue ahead is filled.
    GroupedWallpaperSlot? kept(int id) {
      for (final slot in slots) {
        if (slot.id == id) return slot;
      }
      return null;
    }

    GroupedWallpaperSlot? currentSlot = kept(current);
    if (currentSlot == null) {
      currentSlot = await bakeInto(null);
      current = currentSlot?.id ?? -1;
    }
    final byId = {for (final slot in slots) slot.id: slot};
    if (currentSlot != null) byId[currentSlot.id] = currentSlot;

    if (prefetchAhead >= 1) {
      var nextSlot = kept(next);
      nextSlot ??= await bakeInto(null);
      next = nextSlot?.id ?? -1;
      if (nextSlot != null) byId[nextSlot.id] = nextSlot;
    } else {
      next = -1;
    }
    if (prefetchAhead >= 2) {
      var next2Slot = kept(next2);
      next2Slot ??= await bakeInto(null);
      next2 = next2Slot?.id ?? -1;
      if (next2Slot != null) byId[next2Slot.id] = next2Slot;
    } else {
      next2 = -1;
    }

    final ordered = [current, next, next2].where((id) => id >= 0).toList();
    // An empty group must still record its empty state, even though nothing was
    // baked.
    if (!bakedAny && !mustWrite && current >= 0) return GroupedWallpaperSyncResult.unchanged;
    if (ordered.isEmpty) {
      await store.clearSlots();
    } else {
      await store.pruneSlots(ordered);
    }
    final nextState = GroupedWallpaperState(
      generation: (state?.generation ?? 0) + 1,
      status: current < 0 ? GroupedWallpaperStatus.emptyGroup : GroupedWallpaperStatus.ready,
      groupId: plan.group.id,
      groupNumber: plan.group.number,
      groupName: _resolveName(plan.group),
      count: window.count,
      current: current,
      next: next,
      next2: next2,
      slots: [for (final id in ordered) byId[id]!],
      gestures: plan.gestures,
      bakedAt: now(),
    );
    await store.writeState(nextState);
    await platform.reload();
    groupedWallpaperLog.d('queue.baked current=$current next=$next next2=$next2 count=${window.count}');
    return current < 0 ? GroupedWallpaperSyncResult.empty : GroupedWallpaperSyncResult.baked;
  }

  /// The smallest slot id not in use, so a freed slot is recycled instead of
  /// growing the directory forever.
  static int _nextSlotId(Set<int> used) {
    for (var id = 0; ; id++) {
      if (!used.contains(id)) return id;
    }
  }

  /// Picks the newest entries that are not already in the queue.
  ///
  /// Newest first, skipping files that disappeared since the last scan. A group
  /// with fewer images than the queue depth simply keeps fewer slots: repeating
  /// an image in the queue would make a tap look like it did nothing.
  static List<AvesEntry> _pickEntries(Iterable<AvesEntry> window, {required Set<int> exclude, required int count}) {
    final picked = <AvesEntry>[];
    for (final entry in window) {
      if (picked.length >= count) break;
      if (exclude.contains(entry.id)) continue;
      if (entry.isMissingAtPath) continue;
      picked.add(entry);
    }
    return picked;
  }

  /// Moves the queue one step forward, as a tap on the wallpaper does natively.
  ///
  /// Returns whether anything was promoted: a group with fewer images than the
  /// queue depth has no `next`, and a sync must then keep the current photo
  /// instead of blanking the wallpaper.
  static (GroupedWallpaperState?, bool) _promote(GroupedWallpaperState? state) {
    if (state == null || state.next < 0) return (state, false);
    return (
      state.copyWith(
        current: state.next,
        next: state.next2,
        next2: -1,
        slots: [for (final slot in state.slots) if (slot.id == state.next || slot.id == state.next2) slot],
      ),
      true,
    );
  }

  /// Adopts the slot the native renderer promoted to, when the runtime still
  /// belongs to the state we know about.
  static GroupedWallpaperState? _adoptRuntime(GroupedWallpaperState? state, GroupedWallpaperRuntime? runtime) {
    if (state == null || runtime == null) return state;
    if (!runtime.matches(state)) return state;
    if (runtime.current < 0 || runtime.current == state.current) return state;
    if (state.slotById(runtime.current) == null) return state;
    return state.copyWith(
      current: runtime.current,
      next: runtime.next,
      next2: -1,
      slots: [for (final slot in state.slots) if (slot.id == runtime.current || slot.id == runtime.next) slot],
    );
  }

  /// Whether [previous] is a frame of a real group, i.e. the wallpaper was
  /// following something that has since disappeared.
  static bool _wasPlayingAGroup(GroupedWallpaperState? previous) => previous != null && previous.hasPhoto && previous.groupId.isNotEmpty;

  /// Whether [previous] was baked for another group, or before its range changed.
  ///
  /// Saving a draft or switching the group bumps `updatedAt`, so a changed group
  /// always re-bakes; an unchanged one keeps the queue it already has instead of
  /// cycling through other images on every app start.
  static bool _isStale(GroupedWallpaperPlan plan, GroupedWallpaperState? previous) {
    if (previous == null) return true;
    if (previous.groupId != plan.group.id) return true;
    if (previous.bakedAt < plan.group.updatedAt) return true;
    if (previous.bakedAt < (plan.range?.updatedAt ?? 0)) return true;
    return false;
  }

  /// Whether [previous] already holds the whole queue for the current media set,
  /// with every baked photo on disk.
  ///
  /// The queue length is compared with what the group can actually provide, so a
  /// two-image group is ready with two slots instead of re-baking forever. A state
  /// written by an older build has one slot and therefore upgrades on the first
  /// run.
  Future<bool> _isQueueReady(GroupedWallpaperStateStore store, GroupedWallpaperEntryWindow window, GroupedWallpaperState? previous) async {
    if (previous == null) return false;
    if (previous.status == GroupedWallpaperStatus.emptyGroup && window.count == 0) return true;
    if (previous.status != GroupedWallpaperStatus.ready || !previous.hasPhoto) return false;
    final wanted = window.count < prefetchAhead + 1 ? window.count : prefetchAhead + 1;
    if (previous.queueLength < wanted) return false;
    for (final slot in previous.slots) {
      // The files can be gone while the state still points at them (cache
      // cleanup, manual wipe): a frame that is not on disk is not ready.
      if (store.slotPhotoOf(slot) == null) return false;
    }
    return true;
  }

  /// Freezes the frame on screen: a locked group is not re-baked, so the state
  /// keeps its queue and only records the lock for the notification.
  Future<void> _recordLocked(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, GroupedWallpaperState? previous) async {
    if (previous?.status == GroupedWallpaperStatus.locked && previous?.groupId == plan.group.id) return;
    final state = previous != null
        ? previous.copyWith(generation: previous.generation + 1, status: GroupedWallpaperStatus.locked)
        : GroupedWallpaperState(
            generation: 1,
            status: GroupedWallpaperStatus.locked,
            groupId: plan.group.id,
            groupNumber: plan.group.number,
            groupName: _resolveName(plan.group),
            gestures: plan.gestures,
            bakedAt: now(),
          );
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
      await store.clearSlots();
      final state = plan != null
          ? GroupedWallpaperState(
              generation: (previous?.generation ?? 0) + 1,
              status: GroupedWallpaperStatus.unavailable,
              groupId: plan.group.id,
              groupNumber: plan.group.number,
              groupName: _resolveName(plan.group),
              gestures: plan.gestures,
              bakedAt: now(),
            )
          : GroupedWallpaperState(
              generation: (previous?.generation ?? 0) + 1,
              status: GroupedWallpaperStatus.unavailable,
              groupId: previous?.groupId ?? '',
              groupNumber: previous?.groupNumber ?? 0,
              groupName: previous?.groupName ?? '',
              gestures: previous?.gestures ?? const GroupedWallpaperGestures(),
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
