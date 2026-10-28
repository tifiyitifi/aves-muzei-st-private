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
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_command.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:collection/collection.dart';
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

  /// How many candidates one slot tries before giving up.
  ///
  /// A decode failure steps to the next photo instead of leaving the slot empty.
  static const int maxBakeAttempts = 5;

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
    platform.setSyncRequestHandler(
      onSyncRequested: () => unawaited(prepare(activation: true)),
      onCommand: (command) => unawaited(handleCommand(command)),
    );
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

  /// Absolute path of the home-effect image on screen, for the view page.
  @override
  Future<String?> currentEffectPhotoPath() async {
    final state = await _store?.readState();
    final slot = state?.currentSlot;
    if (slot == null) return null;
    return _store?.slotEffectPhotoOf(slot, lock: false)?.path;
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
  ///
  /// The slot the renderer promoted is read from `runtime.json` inside the run,
  /// so the refill never adopts a promotion the renderer did not write yet.
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

  /// Freezes or resumes the wallpaper without baking anything.
  ///
  /// Only the flag and the generation change, so the renderer keeps the frame it
  /// already uploaded and simply stops promoting. The notification reads the new
  /// flag on the reload it gets from the same write.
  Future<void> setPaused(bool paused) {
    return _serialize(() async {
      await planStore.setPaused(paused);
      final store = _store;
      if (store == null) return;
      final previous = await store.readState();
      if (previous == null || previous.paused == paused) return;
      await store.writeState(previous.copyWith(generation: previous.generation + 1, paused: paused));
      await platform.reload();
    });
  }

  /// Makes the next (`delta > 0`) or previous enabled group current and bakes it.
  ///
  /// A locked target range still displays: baking only reads the range, so the
  /// lock protects editing and browsing, not which group the wallpaper shows.
  Future<GroupedWallpaperSyncResult> switchGroup(int delta) {
    return _serialize(() async {
      final plan = await planStore.switchGroup(delta);
      if (plan.isNone) return GroupedWallpaperSyncResult.unchanged;
      return _run(advance: false, requireActive: false, activation: false, ignoreLock: true);
    });
  }

  /// Shows the photo before the current one, when the state still remembers it.
  ///
  /// The previous photo is re-baked instead of restored from disk: slots are
  /// recycled, so the old file may already show another image.
  Future<GroupedWallpaperSyncResult> previousArtwork() => _enqueue(_runPrevious);

  /// Runs a command sent by the notification.
  Future<void> handleCommand(String command) async {
    final parsed = GroupedWallpaperCommand.tryParse(command);
    if (parsed == null) {
      groupedWallpaperLog.w('ignoring unknown wallpaper command $command');
      return;
    }
    switch (parsed) {
      case GroupedWallpaperCommand.previousArtwork:
        await previousArtwork();
      case GroupedWallpaperCommand.nextArtwork:
        // An explicit "next" is the user asking the wallpaper to play again.
        await setPaused(false);
        await refill(advance: true);
      case GroupedWallpaperCommand.nextGroup:
        await switchGroup(1);
      case GroupedWallpaperCommand.previousGroup:
        await switchGroup(-1);
      case GroupedWallpaperCommand.pause:
        await setPaused(true);
      case GroupedWallpaperCommand.resume:
        await setPaused(false);
    }
  }

  Future<GroupedWallpaperSyncResult> _enqueue(Future<GroupedWallpaperSyncResult> Function() body) => _serialize(body);

  /// Runs [body] after every earlier run, and keeps the queue alive after a
  /// failure so one bad bake cannot disable the engine for the session.
  Future<T> _serialize<T>(Future<T> Function() body) {
    final result = _queue.then((_) => body());
    _queue = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<GroupedWallpaperSyncResult> _run({
    required bool advance,
    required bool requireActive,
    required bool activation,
    bool ignoreLock = false,
  }) async {
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
      if (plan.locked && !ignoreLock) {
        await _recordLocked(store, plan, previous);
        return GroupedWallpaperSyncResult.locked;
      }

      // The renderer may have promoted a slot on its own; adopt it before
      // deciding what to bake, or the freed slot would never be refilled. The
      // renderer writes the runtime synchronously, so this read always sees the
      // promotion that triggered this run.
      final runtime = await store.readRuntime();
      final adopted = _adoptRuntime(previous, runtime);
      final promoted = !identical(adopted, previous);
      final stale = _isStale(plan, adopted);
      final (seed, advanced) = advance && !stale ? _promote(adopted) : (adopted, false);
      final total = await entrySource.count(plan.range);
      // A promoted slot must be recorded even when nothing is baked, so the
      // runtime stops matching and the next run starts from the new current.
      if (!advance && !stale && !promoted && await _isQueueReady(store, total, adopted)) {
        return GroupedWallpaperSyncResult.unchanged;
      }
      return await _bakeQueue(
        store,
        plan,
        total: total,
        seed: stale ? null : seed,
        mustWrite: promoted || advanced,
      );
    } catch (error, stack) {
      groupedWallpaperLog.e('sync failed', error, stack);
      await _recordFailure(store, plan, previous);
      return GroupedWallpaperSyncResult.failed;
    }
  }

  /// Re-bakes the photo shown before the current one and makes it current.
  ///
  /// The queue becomes `previous → current → next`, so "next" returns to the
  /// photo the user came from without a bake. A missing or unreadable entry is a
  /// no-op: the frame on screen must never be replaced by a placeholder just
  /// because a history entry was deleted.
  Future<GroupedWallpaperSyncResult> _runPrevious() async {
    final store = _store;
    if (store == null) return GroupedWallpaperSyncResult.notActive;
    try {
      final plan = await planStore.load();
      final state = await store.readState();
      if (plan.disabled || plan.isNone || state == null || !state.hasPhoto) return GroupedWallpaperSyncResult.unchanged;
      final previous = state.recent.firstWhereOrNull(
        (entry) => (entry.groupId.isEmpty || entry.groupId == state.groupId) && entry.entryId != state.entryId,
      );
      if (previous == null) return GroupedWallpaperSyncResult.unchanged;
      final entry = await entrySource.entryById(plan.range, previous.entryId);
      if (entry == null) return GroupedWallpaperSyncResult.unchanged;

      final current = state.currentSlot!;
      final next = state.nextSlot;
      final id = _nextSlotId({for (final slot in state.slots) slot.id});
      final slot = await _bakeSlot(store, plan, entry, id);
      final ordered = [slot.id, current.id, if (next != null) next.id];
      await store.pruneSlots(ordered);
      final nextState = state.copyWith(
        generation: state.generation + 1,
        status: GroupedWallpaperStatus.ready,
        current: slot.id,
        next: current.id,
        next2: next?.id ?? -1,
        slots: [slot, current, ?next],
        recent: GroupedWallpaperState.promoteRecent(state.recent, slot, groupId: plan.group.id),
        newestEntryId: entry.id > state.newestEntryId ? entry.id : state.newestEntryId,
        ordering: plan.ordering,
        gestures: plan.gestures,
        paused: plan.paused,
        bakedAt: now(),
      );
      await store.writeState(nextState);
      await platform.reload();
      groupedWallpaperLog.d('queue.previous entry=${entry.id} current=${slot.id} next=${current.id}');
      return GroupedWallpaperSyncResult.baked;
    } on GroupedWallpaperBakeException catch (error, stack) {
      groupedWallpaperLog.w('previous photo failed', error, stack);
      return GroupedWallpaperSyncResult.failed;
    } catch (error, stack) {
      groupedWallpaperLog.e('previous photo failed', error, stack);
      return GroupedWallpaperSyncResult.failed;
    }
  }

  /// Bakes every missing slot of the queue for [plan].
  ///
  /// [seed] is the queue and the ordering metadata to keep (current/next
  /// survive), or null to start the group over. [mustWrite] forces a state write
  /// even when nothing was baked, because the renderer already promoted a slot
  /// and its runtime must stop matching.
  Future<GroupedWallpaperSyncResult> _bakeQueue(
    GroupedWallpaperStateStore store,
    GroupedWallpaperPlan plan, {
    required int total,
    GroupedWallpaperState? seed,
    required bool mustWrite,
  }) async {
    final state = seed;
    var current = state?.current ?? -1;
    var next = state?.next ?? -1;
    var next2 = state?.next2 ?? -1;
    final slots = <GroupedWallpaperSlot>[
      for (final slot in state?.slots ?? const <GroupedWallpaperSlot>[])
        // A slot whose file disappeared is not part of the queue any more: it
        // must be re-baked, not kept as an empty frame. The effect files are part
        // of the frame too: a missing one would make the renderer skip the slot.
        if ((slot.id == current || slot.id == next || slot.id == next2) &&
            store.slotPhotoOf(slot) != null &&
            (slot.effectHome.isEmpty || store.effectPhotoExists(slot.effectHome)) &&
            (slot.effectLock.isEmpty || store.effectPhotoExists(slot.effectLock)))
          slot,
    ];
    if (!slots.any((slot) => slot.id == current)) current = -1;
    if (!slots.any((slot) => slot.id == next)) next = -1;
    if (!slots.any((slot) => slot.id == next2)) next2 = -1;

    var cursor = state?.cursor ?? 0;
    var newestEntryId = state?.newestEntryId ?? 0;
    var recent = state?.recent ?? const <GroupedWallpaperRecentEntry>[];
    // Muzei starts its "new photos" marker at zero and walks the whole feed; an
    // Aves group can hold thousands of photos, so "new" means "added after the
    // wallpaper was set up" instead of "not shown yet".
    if (newestEntryId <= 0 && total > 0) {
      newestEntryId = await entrySource.newPhotoMarker(plan.range);
    }
    // The queue plus everything recently shown, so neither a random pick nor the
    // "new photos" walk returns the photo that just left the screen.
    final excluded = <int>{
      for (final slot in slots) slot.entryId,
      for (final entry in recent) entry.entryId,
    };

    // A slot keeps its id while it stays in the queue, so the renderer can keep
    // the texture it already uploaded.
    final usedIds = {for (final slot in slots) slot.id};
    var bakedAny = false;
    Future<GroupedWallpaperSlot?> bakeInto() async {
      for (var attempt = 0; attempt < maxBakeAttempts; attempt++) {
        final pick = await entrySource.pick(
          plan.range,
          ordering: plan.ordering,
          cursor: cursor,
          attempt: attempt,
          newestEntryId: newestEntryId,
          excludeEntryIds: excluded,
        );
        final entry = pick.entry;
        if (entry == null) return null;
        // A real offset advances the in-order walk; a "new photo" pick leaves it
        // alone, exactly like Muzei's repository.
        if (pick.offset >= 0) cursor = pick.offset + 1;
        final id = _nextSlotId(usedIds);
        usedIds.add(id);
        try {
          final slot = await _bakeSlot(store, plan, entry, id);
          bakedAny = true;
          excluded.add(entry.id);
          return slot;
        } on GroupedWallpaperBakeException catch (error, stack) {
          // Step to the next candidate rather than leaving the slot empty.
          groupedWallpaperLog.w('bake failed entry=${entry.id} slot=$id attempt=$attempt', error, stack);
        }
      }
      return null;
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
      currentSlot = await bakeInto();
      current = currentSlot?.id ?? -1;
      // The group has images but none could be picked or decoded: show the
      // placeholder and report a failure, instead of claiming an empty group.
      // A failed prefetch, on the other hand, keeps the frame and the queue.
      if (currentSlot == null && total > 0) {
        throw const GroupedWallpaperBakeException('no usable photo in the group');
      }
    }
    final byId = {for (final slot in slots) slot.id: slot};
    if (currentSlot != null) byId[currentSlot.id] = currentSlot;

    if (prefetchAhead >= 1) {
      var nextSlot = kept(next);
      nextSlot ??= await bakeInto();
      next = nextSlot?.id ?? -1;
      if (nextSlot != null) byId[nextSlot.id] = nextSlot;
    } else {
      next = -1;
    }
    if (prefetchAhead >= 2) {
      var next2Slot = kept(next2);
      next2Slot ??= await bakeInto();
      next2 = next2Slot?.id ?? -1;
      if (next2Slot != null) byId[next2Slot.id] = next2Slot;
    } else {
      next2 = -1;
    }

    // A tap can promote while this run bakes. The renderer writes the runtime
    // with the seed generation, so reading it again keeps the promoted photo
    // instead of writing a state that rewinds to the seed's current.
    final promotion = await _adoptPromotionDuringBake(store, state, byId, current, next, next2);
    if (promotion != null) {
      // The seed's current was on screen until that tap.
      recent = GroupedWallpaperState.promoteRecent(recent, currentSlot, groupId: plan.group.id);
      current = promotion.$1;
      next = promotion.$2;
      next2 = promotion.$3;
      currentSlot = byId[current];
    }

    // Only the photo on screen is "recently shown"; the queued ones are excluded
    // through the queue itself.
    recent = GroupedWallpaperState.promoteRecent(recent, currentSlot, groupId: plan.group.id);
    if (currentSlot != null && currentSlot.entryId > newestEntryId) {
      newestEntryId = currentSlot.entryId;
    }

    final ordered = [current, next, next2].where((id) => id >= 0).toList();
    // An empty group must still record its empty state, even though nothing was
    // baked.
    if (!bakedAny && !mustWrite && promotion == null && current >= 0) return GroupedWallpaperSyncResult.unchanged;
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
      count: total,
      current: current,
      next: next,
      next2: next2,
      slots: [for (final id in ordered) byId[id]!],
      recent: recent,
      cursor: cursor,
      newestEntryId: newestEntryId,
      ordering: plan.ordering,
      gestures: plan.gestures,
      paused: plan.paused,
      bakedAt: now(),
    );
    await store.writeState(nextState);
    await platform.reload();
    groupedWallpaperLog.d('queue.baked current=$current next=$next next2=$next2 count=$total cursor=$cursor');
    return current < 0 ? GroupedWallpaperSyncResult.empty : GroupedWallpaperSyncResult.baked;
  }

  /// Bakes [entry] into slot [id], including the group's effect images.
  ///
  /// Shared by the forward queue and "previous photo", so both write exactly the
  /// same file set and the renderer never sees a half-baked slot.
  Future<GroupedWallpaperSlot> _bakeSlot(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, AvesEntry entry, int id) async {
    final targetSize = await _resolveTargetSize();
    final bake = await baker.bake(
      entry: entry,
      targetSize: targetSize,
      home: plan.effects.home,
      lock: plan.effects.effectiveLock,
    );
    final photo = await store.writeSlotPhoto(id, bake.sharpPng);
    // An identity effect is byte-identical to the sharp photo: pointing at the
    // same file avoids a second copy of a multi-megabyte PNG.
    final effectHome = identical(bake.effectsHomePng, bake.sharpPng)
        ? photo
        : await store.writeSlotPhoto(id, bake.effectsHomePng, name: GroupedWallpaperStateStore.slotEffectHomeFileName);
    final effectLock = identical(bake.effectsLockPng, bake.sharpPng)
        ? photo
        : identical(bake.effectsLockPng, bake.effectsHomePng)
            ? effectHome
            : await store.writeSlotPhoto(id, bake.effectsLockPng, name: GroupedWallpaperStateStore.slotEffectLockFileName);
    return GroupedWallpaperSlot(
      id: id,
      entryId: entry.id,
      uri: entry.uri,
      title: entry.bestTitle ?? '',
      photo: photo,
      effectHome: effectHome,
      effectLock: effectLock,
      width: bake.size.width.round(),
      height: bake.size.height.round(),
      darkness: bake.darkness,
    );
  }

  /// The smallest slot id not in use, so a freed slot is recycled instead of
  /// growing the directory forever.
  static int _nextSlotId(Set<int> used) {
    for (var id = 0; ; id++) {
      if (!used.contains(id)) return id;
    }
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
  ///
  /// Forward only: a promotion can only target a slot queued after [state]'s
  /// current. A runtime pointing at the current slot, or at a slot that left the
  /// queue, is not a promotion of this state and is ignored.
  static GroupedWallpaperState? _adoptRuntime(GroupedWallpaperState? state, GroupedWallpaperRuntime? runtime) {
    if (state == null || runtime == null) return state;
    if (!runtime.matches(state)) return state;
    final queue = [state.current, state.next, state.next2].where((id) => id >= 0).toList();
    final index = queue.indexOf(runtime.current);
    if (index <= 0) return state;
    final next = index + 1 < queue.length ? queue[index + 1] : -1;
    return state.copyWith(
      current: queue[index],
      next: next,
      next2: -1,
      slots: [for (final slot in state.slots) if (slot.id == queue[index] || slot.id == next) slot],
    );
  }

  /// Adopts a promotion the renderer made while [seed]'s queue was baking.
  ///
  /// Returns the queue after the promotion, or null when the runtime is not a
  /// promotion of [seed] or targets a slot this run has not baked. The renderer
  /// writes the runtime synchronously with the seed generation, so a matching
  /// generation is exactly "promoted while this bake was running".
  Future<(int, int, int)?> _adoptPromotionDuringBake(
    GroupedWallpaperStateStore store,
    GroupedWallpaperState? seed,
    Map<int, GroupedWallpaperSlot> baked,
    int current,
    int next,
    int next2,
  ) async {
    if (seed == null) return null;
    final runtime = await store.readRuntime();
    if (runtime == null || !runtime.matches(seed)) return null;
    // A promotion always targets a slot of the seed queue, ahead of its current.
    // Checking the seed queue (not the rebuilt one) also rejects a slot id that
    // the bake recycled for another photo.
    final seedQueue = [seed.current, seed.next, seed.next2].where((id) => id >= 0).toList();
    if (seedQueue.indexOf(runtime.current) <= 0) return null;
    final queue = [current, next, next2].where((id) => id >= 0).toList();
    final index = queue.indexOf(runtime.current);
    if (index <= 0 || !baked.containsKey(runtime.current)) return null;
    return (queue[index], index + 1 < queue.length ? queue[index + 1] : -1, -1);
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
  Future<bool> _isQueueReady(GroupedWallpaperStateStore store, int total, GroupedWallpaperState? previous) async {
    if (previous == null) return false;
    if (previous.status == GroupedWallpaperStatus.emptyGroup && total == 0) return true;
    if (previous.status != GroupedWallpaperStatus.ready || !previous.hasPhoto) return false;
    final wanted = total < prefetchAhead + 1 ? total : prefetchAhead + 1;
    if (previous.queueLength < wanted) return false;
    for (final slot in previous.slots) {
      // The files can be gone while the state still points at them (cache
      // cleanup, manual wipe): a frame that is not on disk is not ready.
      if (store.slotPhotoOf(slot) == null) return false;
      if (slot.effectHome.isNotEmpty && !store.effectPhotoExists(slot.effectHome)) return false;
      if (slot.effectLock.isNotEmpty && !store.effectPhotoExists(slot.effectLock)) return false;
    }
    return true;
  }

  /// Freezes the frame on screen: a locked group is not re-baked, so the state
  /// keeps its queue and only records the lock for the notification.
  Future<void> _recordLocked(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, GroupedWallpaperState? previous) async {
    if (previous?.status == GroupedWallpaperStatus.locked && previous?.groupId == plan.group.id) return;
    final state = previous != null
        ? previous.copyWith(generation: previous.generation + 1, status: GroupedWallpaperStatus.locked, paused: plan.paused)
        : GroupedWallpaperState(
            generation: 1,
            status: GroupedWallpaperStatus.locked,
            groupId: plan.group.id,
            groupNumber: plan.group.number,
            groupName: _resolveName(plan.group),
            ordering: plan.ordering,
            gestures: plan.gestures,
            paused: plan.paused,
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
              paused: plan.paused,
              bakedAt: now(),
            )
          : GroupedWallpaperState(
              generation: (previous?.generation ?? 0) + 1,
              status: GroupedWallpaperStatus.unavailable,
              groupId: previous?.groupId ?? '',
              groupNumber: previous?.groupNumber ?? 0,
              groupName: previous?.groupName ?? '',
              gestures: previous?.gestures ?? const GroupedWallpaperGestures(),
              paused: previous?.paused ?? false,
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
