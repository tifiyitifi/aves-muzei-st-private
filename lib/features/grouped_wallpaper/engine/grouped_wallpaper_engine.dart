import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_entry_source.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_history_recorder.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_names.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_plan.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_command.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
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

  /// Writes the usage history; injectable so a test can assert the rows without
  /// opening a database.
  final GroupedWallpaperHistoryRecorder history;

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
    GroupedWallpaperHistoryRecorder? history,
    Future<Size?> Function()? targetSize,
    int Function()? now,
  })  : baker = baker ?? GroupedWallpaperBaker(),
        planStore = planStore ?? SavedGroupedWallpaperPlanStore(),
        entrySource = entrySource ?? GroupedWallpaperDbEntrySource(),
        nameResolver = nameResolver ?? resolveGroupedWallpaperName,
        link = link ?? wallpaperEngineLink,
        history = history ?? DbGroupedWallpaperHistoryRecorder(),
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
    final active = await link.refreshActive();
    await link.refreshDisabled();
    // A service the system killed never runs its cleanup, so its bar can outlive
    // the wallpaper. When this is no longer the system wallpaper, drop it now
    // instead of leaving it until the next boot.
    if (!active) await platform.cancelNotification();
  }

  void detach() {
    platform.setSyncRequestHandler();
    link.detach();
    _store = null;
  }

  @override
  Future<bool> isActive() => platform.isActive();

  @override
  Future<bool> restoreOffer() => platform.restoreOffer();

  @override
  Future<bool> isDisabled() async => (await planStore.load()).disabled;

  @override
  Future<bool> openChooser() => platform.openChooser();

  /// The state the renderer is showing, or null when nothing was ever baked.
  @override
  Future<GroupedWallpaperState?> readState() async => await _store?.readState();

  /// [readState] with [GroupedWallpaperState.current] moved to the slot the
  /// engine is actually drawing.
  ///
  /// `state.json` is what Dart baked; the renderer may have promoted a slot on
  /// its own, or kept drawing one a reload no longer calls current. Reading
  /// `current` alone therefore describes a photo the user may not be looking at,
  /// which is what made the three-finger view differ from the wallpaper. A
  /// missing or pruned slot falls back to the state: a stale answer beats none.
  @override
  Future<GroupedWallpaperState?> readDisplayedState() async {
    final state = await _store?.readState();
    if (state == null) return null;
    final displayed = await platform.displayedSlot();
    if (displayed == null || state.slotById(displayed) == null) return state;
    return state.copyWith(current: displayed);
  }

  /// Absolute path of the photo on screen, for the view page.
  @override
  Future<String?> currentPhotoPath() async {
    final state = await readDisplayedState();
    final slot = state?.currentSlot;
    if (slot == null) return null;
    return _store?.slotPhotoOf(slot)?.path;
  }

  /// Absolute path of the home-effect image on screen, for the view page.
  @override
  Future<String?> currentEffectPhotoPath() async {
    final state = await readDisplayedState();
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

  @override
  Future<bool> isNotificationEnabled() async => (await planStore.load()).notification;

  /// Records whether the wallpaper may show its notification bar.
  ///
  /// The bar belongs to the service, so the flag has to reach `state.json` even
  /// when no frame is baked: the app rewrites the state the service is reading and
  /// then asks it to refresh, which is what makes the toggle immediate.
  @override
  Future<void> setNotification(bool enabled) async {
    await planStore.setNotification(enabled);
    final store = _store;
    if (store != null) {
      final state = await store.readState();
      if (state != null && state.notification != enabled) {
        // No generation bump: the frame on screen does not change, and a bump
        // would make the renderer's runtime stale and cost a re-bake.
        await store.writeState(state.copyWith(notification: enabled));
      }
    }
    await platform.refreshNotification();
  }

  @override
  Future<bool> isScrollEffectEnabled() async => (await planStore.load()).scrollEffect;

  /// Records the home-screen scroll effect switch and re-bakes the frame now.
  ///
  /// The layout is part of the staleness check, so the following prepare bakes
  /// exactly once: without it the switch would only apply to the next photo.
  @override
  Future<void> setScrollEffect(bool enabled) async {
    await planStore.setScrollEffect(enabled);
    await prepare();
  }

  /// Records how many photos the usage history keeps and tells the bar about it.
  ///
  /// The value travels with the state so the notification can grey its "previous"
  /// button without asking the app. No generation bump: the frame on screen does
  /// not change, and a bump would cost a re-bake. Nothing is pruned here: a lower
  /// limit only takes effect on the next shown photo.
  @override
  Future<void> setHistoryLimit(int limit) {
    return _serialize(() async {
      final value = GroupedWallpaperHistoryLimit.sanitize(limit);
      await planStore.setHistoryLimit(value);
      final store = _store;
      if (store == null) return;
      final state = await store.readState();
      if (state == null || state.historyLimit == value) return;
      await store.writeState(state.copyWith(historyLimit: value));
      await platform.refreshNotification();
    });
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
  /// flag on the reload it gets from the same write. A frozen wallpaper also stops
  /// waking up for auto-advance; resuming starts a fresh countdown.
  Future<void> setPaused(bool paused) {
    return _serialize(() async {
      await planStore.setPaused(paused);
      await _scheduleAutoAdvance(await planStore.load());
      final store = _store;
      if (store == null) return;
      final previous = await store.readState();
      if (previous == null || previous.paused == paused) return;
      await store.writeState(previous.copyWith(generation: previous.generation + 1, paused: paused));
      await platform.reload();
    });
  }

  /// Re-applies the current group's auto-advance interval to the scheduler.
  ///
  /// The page calls this after editing a group's interval or ordering: the values
  /// only affect the schedule, so no frame is re-baked.
  @override
  Future<void> refreshSchedule() {
    return _serialize(() async => _scheduleAutoAdvance(await planStore.load()));
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
      // An interval run is already on the countdown, so only the runs the page or
      // the service start schedule it, and an unchanged interval keeps its
      // pending run instead of restarting.
      if (!advance) await _scheduleAutoAdvance(plan);
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
      final surface = await _resolveTargetSize();
      final scrollEffect = await _effectiveScrollEffect(plan);
      final groupStale = _isStale(plan, adopted);
      final layoutStale = _isLayoutStale(adopted, surface, scrollEffect);
      final stale = groupStale || layoutStale;
      // A layout change re-bakes the photos already queued into the same slots,
      // so a rotation or the switch keeps the photo on screen (and a freeze)
      // instead of restarting the group.
      final rebake = !groupStale && layoutStale ? await _layoutRebake(plan, adopted) : const <int, AvesEntry>{};
      final rebakeComplete = !groupStale && layoutStale && rebake.isNotEmpty;
      // A frozen wallpaper keeps the photo on screen, even when the interval or a
      // sync asks for the next one.
      final (seed, advanced) = advance && !stale && !plan.paused ? _promote(adopted) : (adopted, false);
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
        previous: previous,
        // A group change starts over; a layout-only change keeps the queue.
        seed: groupStale || (layoutStale && !rebakeComplete) ? null : seed,
        mustWrite: promoted || advanced,
        surface: surface,
        scrollEffect: scrollEffect,
        rebakeEntries: rebakeComplete ? rebake : const {},
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
      // Recording off means the history is off: "previous" would step to a photo
      // the history no longer keeps, so the button is inert on both sides.
      if (plan.historyLimit <= 0) return GroupedWallpaperSyncResult.unchanged;
      final previous = state.recent.firstWhereOrNull(
        (entry) => (entry.groupId.isEmpty || entry.groupId == state.groupId) && entry.entryId != state.entryId,
      );
      if (previous == null) return GroupedWallpaperSyncResult.unchanged;
      final entry = await entrySource.entryById(plan.range, previous.entryId);
      if (entry == null) return GroupedWallpaperSyncResult.unchanged;

      final surface = await _resolveTargetSize();
      final scrollEffect = await _effectiveScrollEffect(plan);
      // Every slot carries the old geometry after a rotation or a switch change:
      // re-bake the queue instead of stacking one new-layout photo in front of
      // stale ones the renderer would promote next.
      if (_isLayoutStale(state, surface, scrollEffect)) {
        return await _run(advance: false, requireActive: false, activation: false);
      }

      final current = state.currentSlot!;
      final next = state.nextSlot;
      final id = _nextSlotId({for (final slot in state.slots) slot.id});
      final slot = await _bakeSlot(store, plan, entry, id, surface, scrollEffect);
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
        surfaceWidth: surface.width.round(),
        surfaceHeight: surface.height.round(),
        scrollEffect: scrollEffect,
        historyLimit: plan.historyLimit,
        bakedAt: now(),
      );
      await store.writeState(nextState);
      await _recordShown(plan, slot, state);
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
    GroupedWallpaperState? previous,
    GroupedWallpaperState? seed,
    required bool mustWrite,
    required Size surface,
    required bool scrollEffect,
    Map<int, AvesEntry> rebakeEntries = const {},
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
          final slot = await _bakeSlot(store, plan, entry, id, surface, scrollEffect);
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
      // A slot queued for a layout re-bake must not be kept as it is: its file
      // still has the old geometry.
      if (rebakeEntries.containsKey(id)) return null;
      for (final slot in slots) {
        if (slot.id == id) return slot;
      }
      return null;
    }

    /// Re-bakes a queued slot's own photo into the same id for the new layout.
    Future<GroupedWallpaperSlot?> bakeSame(int id) async {
      final entry = rebakeEntries[id];
      if (entry == null) return null;
      try {
        final slot = await _bakeSlot(store, plan, entry, id, surface, scrollEffect);
        bakedAny = true;
        return slot;
      } on GroupedWallpaperBakeException catch (error, stack) {
        groupedWallpaperLog.w('layout re-bake failed entry=${entry.id} slot=$id', error, stack);
        return null;
      }
    }

    GroupedWallpaperSlot? currentSlot = kept(current) ?? await bakeSame(current);
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
      var nextSlot = kept(next) ?? await bakeSame(next);
      nextSlot ??= await bakeInto();
      next = nextSlot?.id ?? -1;
      if (nextSlot != null) byId[nextSlot.id] = nextSlot;
    } else {
      next = -1;
    }
    if (prefetchAhead >= 2) {
      var next2Slot = kept(next2) ?? await bakeSame(next2);
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
      notification: plan.notification,
      surfaceWidth: surface.width.round(),
      surfaceHeight: surface.height.round(),
      scrollEffect: scrollEffect,
      historyLimit: plan.historyLimit,
      bakedAt: now(),
    );
    await store.writeState(nextState);
    await _recordShown(plan, currentSlot, previous);
    await platform.reload();
    groupedWallpaperLog.d('queue.baked current=$current next=$next next2=$next2 count=$total cursor=$cursor surface=${surface.width.round()}x${surface.height.round()} scrollEffect=$scrollEffect');
    return current < 0 ? GroupedWallpaperSyncResult.empty : GroupedWallpaperSyncResult.baked;
  }

  /// Bakes [entry] into slot [id], including the group's effect images.
  ///
  /// Shared by the forward queue and "previous photo", so both write exactly the
  /// same file set and the renderer never sees a half-baked slot.
  Future<GroupedWallpaperSlot> _bakeSlot(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, AvesEntry entry, int id, Size surface, bool scrollEffect) async {
    final targetSize = scrollEffect ? _scrollTarget(surface, entry) : surface;
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

  /// Whether [previous] was baked for another surface or scroll effect.
  ///
  /// The launcher changes the surface on rotation and when it updates its
  /// dimension hints, and the switch changes the width of every frame: keeping
  /// the old texture would stretch or crop it, so either re-bakes once.
  static bool _isLayoutStale(GroupedWallpaperState? previous, Size surface, bool scrollEffect) {
    if (previous == null) return true;
    if (previous.surfaceWidth != surface.width.round()) return true;
    if (previous.surfaceHeight != surface.height.round()) return true;
    return previous.scrollEffect != scrollEffect;
  }

  /// The entries of the queue, so a layout change re-bakes them into the same
  /// slots instead of picking other photos.
  ///
  /// Returns an empty map when a slot's entry is gone: the caller then restarts
  /// the group rather than leave one frame at the old size.
  Future<Map<int, AvesEntry>> _layoutRebake(GroupedWallpaperPlan plan, GroupedWallpaperState? state) async {
    if (state == null) return const {};
    final entries = <int, AvesEntry>{};
    for (final slot in state.slots) {
      final entry = await entrySource.entryById(plan.range, slot.entryId);
      if (entry == null) return const {};
      entries[slot.id] = entry;
    }
    return entries;
  }

  /// Whether frames should keep the photo's whole width for the launcher to pan.
  ///
  /// The switch is the user's, but a launcher that never pans (`xOffsetStep` 0)
  /// has nothing to pan with, so a wide frame there would only crop the sides. An
  /// unknown step means no offset callback arrived yet: follow the switch.
  Future<bool> _effectiveScrollEffect(GroupedWallpaperPlan plan) async {
    if (!plan.scrollEffect) return false;
    final step = await platform.scrollStep();
    return step == null || step > 0;
  }

  /// The photo's whole width at the surface height, capped by the texture limit.
  ///
  /// The renderer maps the launcher's `0..1` offset onto the whole texture, so a
  /// frame this wide lets the home pages show the rest of the photo. A photo
  /// narrower than the surface keeps the surface size: there is nothing to pan.
  static Size _scrollTarget(Size surface, AvesEntry entry) {
    final display = entry.displaySize;
    if (display.width <= 0 || display.height <= 0) return surface;
    final width = surface.height * display.width / display.height;
    if (!width.isFinite || width <= surface.width) return surface;
    return Size(math.min(width, GroupedWallpaperBaker.maxDimension.toDouble()), surface.height);
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

  /// Records the photo now on screen, when it is not the one already there.
  ///
  /// Only a change of the visible photo is recorded: a layout re-bake, a freeze, a
  /// resume, a disable or a lock all keep the same entry, so they add no row. A
  /// group switch is a change even when the same photo happens to be in both
  /// groups, because the history is per group.
  Future<void> _recordShown(GroupedWallpaperPlan plan, GroupedWallpaperSlot? slot, GroupedWallpaperState? previous) async {
    if (slot == null || slot.entryId <= 0) return;
    if (plan.historyLimit <= 0) return;
    final shown = previous?.currentSlot;
    if (shown != null && shown.entryId == slot.entryId && previous?.groupId == plan.group.id) return;
    try {
      await history.record(
        entryId: slot.entryId,
        groupId: plan.group.id,
        groupName: plan.group.name,
        groupNumber: plan.group.number,
        usedAt: now(),
        limit: plan.historyLimit,
      );
    } catch (error, stack) {
      // A failed write must never cost the user their wallpaper.
      groupedWallpaperLog.w('failed to record the wallpaper history', error, stack);
    }
  }

  /// Freezes the frame on screen: a locked group is not re-baked, so the state
  /// keeps its queue and only records the lock for the notification.
  Future<void> _recordLocked(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, GroupedWallpaperState? previous) async {
    if (previous?.status == GroupedWallpaperStatus.locked && previous?.groupId == plan.group.id) return;
    final state = previous != null
        ? previous.copyWith(generation: previous.generation + 1, status: GroupedWallpaperStatus.locked, paused: plan.paused, historyLimit: plan.historyLimit)
        : GroupedWallpaperState(
            generation: 1,
            status: GroupedWallpaperStatus.locked,
            groupId: plan.group.id,
            groupNumber: plan.group.number,
            groupName: _resolveName(plan.group),
            ordering: plan.ordering,
            gestures: plan.gestures,
            paused: plan.paused,
            notification: plan.notification,
            historyLimit: plan.historyLimit,
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
              notification: plan.notification,
              historyLimit: plan.historyLimit,
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
              notification: previous?.notification ?? true,
              historyLimit: previous?.historyLimit ?? GroupedWallpaperHistoryLimit.defaultLimit,
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

  /// Keeps the native interval in step with the group that is playing.
  ///
  /// A frozen, disabled or group-0 wallpaper schedules nothing, so it does not
  /// wake up for a frame it would refuse to show. The scheduler keeps an
  /// unchanged interval's pending run, so this is safe to call on every run.
  Future<void> _scheduleAutoAdvance(GroupedWallpaperPlan plan) async {
    final seconds = plan.disabled || plan.paused || plan.isNone ? 0 : plan.interval.seconds;
    await platform.scheduleAutoAdvance(seconds);
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
