import 'dart:async';
import 'dart:convert';
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
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
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
/// The queue is `previous → current → next`, both neighbours baked: the renderer
/// promotes either side without waiting for Flutter (a wallpaper tap goes
/// forward, the bar's "previous" goes back), records what it did in
/// `runtime.json`, and Dart refills the frame it left behind from the cache. So
/// stepping through the usage history needs no bake, in either direction.
class GroupedWallpaperEngine implements WallpaperEngineConnection {
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

  /// Whether the group-switch lock is on, injectable so a test does not need the
  /// lock service's database and encrypted store.
  final bool Function() _groupSwitchLocked;

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
    bool Function()? groupSwitchLocked,
  })  : baker = baker ?? GroupedWallpaperBaker(),
        planStore = planStore ?? SavedGroupedWallpaperPlanStore(),
        entrySource = entrySource ?? GroupedWallpaperDbEntrySource(),
        nameResolver = nameResolver ?? resolveGroupedWallpaperName,
        link = link ?? wallpaperEngineLink,
        history = history ?? DbGroupedWallpaperHistoryRecorder(),
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _groupSwitchLocked = groupSwitchLocked ?? (() => wallpaperLockService.groupSwitchLocked),
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
    // The bar can lock without the app running, so its request is persisted on
    // disk: adopting it here is what keeps a tap from being lost between the tap
    // and the next start.
    final adoptedLock = await _adoptLockRequest();
    await _upgradeState();
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
    // The bar was showing a pending lock; the persisted one has to replace it,
    // or the group buttons stay greyed until the next bake.
    if (adoptedLock) await refreshLock();
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

  /// Records how many photos the usage history keeps and tells the bar about it.
  ///
  /// The value travels with the state so the notification can grey its "previous"
  /// button without asking the app. No generation bump: the frame on screen does
  /// not change, and a bump would cost a re-bake. Lowering the limit trims the
  /// rewind stack now, so "previous" cannot walk further back than the records
  /// the user chose to keep.
  @override
  Future<void> setHistoryLimit(int limit) {
    return _serialize(() async {
      final value = GroupedWallpaperHistoryLimit.sanitize(limit);
      await planStore.setHistoryLimit(value);
      final store = _store;
      if (store == null) return;
      final state = await store.readState();
      if (state == null) return;
      final kept = value <= 0 ? const <GroupedWallpaperRewindEntry>[] : state.rewind.take(value).toList(growable: false);
      // The current photo must stay the anchor even when the new limit is
      // smaller than how far the user had walked back.
      final current = state.currentSlot;
      final currentKept = current != null && state.rewindCursor < kept.length && kept[state.rewindCursor].entryId == current.entryId;
      final rewind = currentKept || current == null ? kept : <GroupedWallpaperRewindEntry>[GroupedWallpaperRewindEntry(entryId: current.entryId)];
      final rewindCursor = currentKept ? state.rewindCursor : 0;
      if (state.historyLimit == value && state.rewind.length == rewind.length && state.rewindCursor == rewindCursor) return;
      final updated = state.copyWith(historyLimit: value, rewind: rewind, rewindCursor: rewindCursor);
      await store.writeState(updated);
      await store.pruneFrames(keep: _framePaths(updated), maxFrames: value <= 0 ? 6 : value);
      await platform.refreshNotification();
    });
  }

  /// Drops the rewind stack after the usage history was cleared.
  ///
  /// The stack is the usage history as the wallpaper navigates it, so clearing
  /// the records must make "previous" unavailable instead of keeping a private
  /// copy of them. The current photo stays as the anchor.
  @override
  Future<void> clearRewind() {
    return _serialize(() async {
      final store = _store;
      if (store == null) return;
      final state = await store.readState();
      if (state == null) return;
      final current = state.currentSlot;
      final rewind = current == null ? const <GroupedWallpaperRewindEntry>[] : [GroupedWallpaperRewindEntry(entryId: current.entryId)];
      if (state.rewind.length == rewind.length && state.rewindCursor == 0) return;
      final cleared = state.copyWith(generation: state.generation + 1, rewind: rewind, rewindCursor: 0, previous: -1);
      await store.writeState(cleared);
      // The frames of the cleared records are the same private copy: dropping the
      // records must drop them too, not just hide the button.
      await store.clearFrames(keep: _framePaths(cleared));
      await platform.reload();
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
  /// Re-applies the current group's auto-advance interval to the scheduler.
  ///
  /// The page calls this after editing a group's interval or ordering: the values
  /// only affect the schedule, so no frame is re-baked.
  @override
  Future<void> refreshSchedule() {
    return _serialize(() async => _scheduleAutoAdvance(await planStore.load()));
  }

  /// Records the group-switch lock and re-posts the bar.
  ///
  /// Only the bar's group buttons change: the photo on screen and the queue are
  /// untouched, so this never bakes.
  @override
  Future<void> refreshLock() {
    return _serialize(() async {
      final store = _store;
      if (store == null) return;
      final state = await store.readState();
      if (state == null) return;
      final locked = _groupSwitchLocked();
      final lockedGroupId = wallpaperLockService.groupSwitchLockedGroupId ?? '';
      final changed = state.switchLocked != locked || state.switchLockedGroupId != lockedGroupId;
      if (changed) {
        await store.writeState(state.copyWith(generation: state.generation + 1, switchLocked: locked, switchLockedGroupId: lockedGroupId));
        await platform.reload();
        await platform.refreshNotification();
      }
      groupedWallpaperLog.i('refreshLock switchLocked=$locked wrote=$changed');
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

  /// Shows the older usage record when the walk still has one.
  @override
  Future<GroupedWallpaperSyncResult> previousArtwork() => _enqueue(() => _runRewind(1));

  /// Shows the newer usage record, or a new photo from the newest one.
  @override
  Future<GroupedWallpaperSyncResult> nextArtwork() => _enqueue(() => _run(advance: true, requireActive: false, activation: false));

  /// Refuses a group switch sent by the notification while its lock is on.
  ///
  /// The native bar already greys those buttons, so this only covers a bar
  /// posted before the lock changed.
  bool _refuseLockedGroupSwitch() {
    if (!_groupSwitchLocked()) return false;
    groupedWallpaperLog.i('ignoring a group switch: group switching is locked');
    return true;
  }

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
        await nextArtwork();
      case GroupedWallpaperCommand.nextGroup:
        if (_refuseLockedGroupSwitch()) return;
        await switchGroup(1);
      case GroupedWallpaperCommand.previousGroup:
        if (_refuseLockedGroupSwitch()) return;
        await switchGroup(-1);
      case GroupedWallpaperCommand.lockGroup:
        await _lockGroupFromBar();
    }
  }

  /// Locks the group on screen, as the notification's lock button asks.
  ///
  /// The bar already shows the lock and greys the group buttons, so this only
  /// persists it: the app's own guard is what refuses the next switch, and the
  /// refreshed state tells the bar that the lock is real instead of pending.
  Future<void> _lockGroupFromBar() async {
    if (await _adoptLockRequest()) {
      await refreshLock();
      return;
    }
    final groupId = (await _store?.readState())?.groupId ?? '';
    if (groupId.isEmpty) {
      groupedWallpaperLog.w('ignoring a group lock with no group on screen');
      return;
    }
    await wallpaperLockService.init();
    await wallpaperLockService.lockGroup(groupId);
    await refreshLock();
    groupedWallpaperLog.i('lock.bar applied group=$groupId');
  }

  /// Rewrites a state from before the rewind stack.
  ///
  /// Parsing seeds the stack from `recent`; writing it back also puts
  /// `canPrevious` in `state.json`, so the bar stops greying "previous" without
  /// waiting for the next photo.
  Future<void> _upgradeState() async {
    final store = _store;
    if (store == null) return;
    try {
      final state = await store.readState();
      if (state == null || !state.needsUpgrade) return;
      await store.writeState(state.copyWith(version: GroupedWallpaperState.currentVersion, needsUpgrade: false));
      await platform.refreshNotification();
      groupedWallpaperLog.i('state upgraded version=${state.version} -> ${GroupedWallpaperState.currentVersion}');
    } catch (error, stack) {
      // A failed upgrade must not keep the engine from attaching.
      groupedWallpaperLog.w('failed to upgrade the wallpaper state', error, stack);
    }
  }

  /// Persists a lock the notification recorded while the app was not listening.
  ///
  /// The request names the group that was on screen at tap time, so a group switch
  /// that completed in between cannot move the lock to another group.
  ///
  /// @return whether a request was waiting.
  Future<bool> _adoptLockRequest() async {    final store = _store;
    if (store == null) return false;
    final groupId = await store.readLockRequest();
    if (groupId == null) return false;
    await wallpaperLockService.init();
    await wallpaperLockService.lockGroup(groupId);
    await store.clearLockRequest();
    groupedWallpaperLog.i('lock.request adopted group=$groupId');
    return true;
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
      final promoted = adopted != null && !identical(adopted.state, previous);
      final surface = await _resolveTargetSize();
      final scrollEffect = await _effectiveScrollEffect(plan);
      final groupStale = _isStale(plan, adopted?.state ?? previous);
      final layoutStale = _isLayoutStale(adopted?.state ?? previous, surface, scrollEffect);
      final total = await entrySource.count(plan.range);
      // A state written before the entry-keyed cache has to be rewritten once so
      // the native bar learns `canPrevious` instead of staying greyed.
      final migrated = previous?.needsUpgrade == true;

      // A group change, or a photo that left the range, starts the walk over.
      final current = adopted?.state ?? previous;
      if (groupStale || current == null || !current.hasPhoto) {
        return await _startOver(store, plan, previous, total: total, surface: surface, scrollEffect: scrollEffect);
      }

      // A forward step walks the usage history: both neighbours are already
      // baked, so a double tap, the interval and the bar's "next" are the same
      // move, and only the newest record creates a new photo.
      final move = advance ? _moveTo(current, current.next, navigated: true) : null;
      if (move != null) {
        final result = await _settle(
          store,
          plan,
          move.state,
          total: total,
          surface: surface,
          scrollEffect: scrollEffect,
          newPhoto: move.newPhoto,
          navigated: true,
        );
        if (result == GroupedWallpaperSyncResult.baked) await _restartAutoAdvance(plan);
        return result;
      }

      // A promoted slot must be recorded even when nothing is baked, so the
      // runtime stops matching and the next run starts from the new current.
      if (!layoutStale && !promoted && !migrated && await _isQueueReady(store, total, current)) {
        return GroupedWallpaperSyncResult.unchanged;
      }
      return await _settle(
        store,
        plan,
        current,
        total: total,
        surface: surface,
        scrollEffect: scrollEffect,
        newPhoto: adopted?.newPhoto ?? false,
        // The renderer may have kept a frame; a plain settle must not claim it
        // was a history step, or it would override that decision.
        navigated: false,
      );
    } catch (error, stack) {
      groupedWallpaperLog.e('sync failed', error, stack);
      await _recordFailure(store, plan, previous);
      return GroupedWallpaperSyncResult.failed;
    }
  }

  /// Steps the wallpaper through the usage history by [delta].
  ///
  /// `+1` is "previous" and `-1` is "next". The step only changes which queued
  /// frame is drawn: both neighbours are already baked, so a tap never waits for
  /// a bake, and the frame that left the queue is refilled afterwards from the
  /// cache. A record that left the media set is skipped; at the end of the walk
  /// the stack is trimmed so the bar greys its button instead of offering a step
  /// that does nothing.
  Future<GroupedWallpaperSyncResult> _runRewind(int delta) async {
    final store = _store;
    if (store == null) return GroupedWallpaperSyncResult.notActive;
    try {
      final plan = await planStore.load();
      final state = await store.readState();
      if (plan.disabled || plan.isNone || state == null || !state.hasPhoto) return GroupedWallpaperSyncResult.unchanged;
      if (plan.historyLimit <= 0) return GroupedWallpaperSyncResult.unchanged;
      final target = delta > 0 ? state.previous : state.next;
      final targetSlot = state.slotById(target);
      // The queued frame may belong to a photo that left the media set since it
      // was baked (a locked vault, a hidden filter): stepping to it would bring a
      // hidden photo back, so the walk stops here instead.
      final entry = targetSlot == null ? null : await entrySource.entryById(plan.range, targetSlot.entryId);
      if (targetSlot == null || entry == null) {
        if (delta > 0 && state.previous >= 0) await _trimRewind(store, state, entryId: targetSlot?.entryId);
        return GroupedWallpaperSyncResult.unchanged;
      }
      final move = _moveTo(state, target, navigated: true);
      if (move == null) return GroupedWallpaperSyncResult.unchanged;
      final surface = await _resolveTargetSize();
      final scrollEffect = await _effectiveScrollEffect(plan);
      // A layout change must never swallow the step: the frames are re-baked for
      // the new surface as part of settling.
      final result = await _settle(
        store,
        plan,
        move.state,
        total: await entrySource.count(plan.range),
        surface: surface,
        scrollEffect: scrollEffect,
        newPhoto: move.newPhoto,
        navigated: true,
      );
      if (result == GroupedWallpaperSyncResult.baked) await _restartAutoAdvance(plan);
      groupedWallpaperLog.d('queue.step delta=$delta current=${move.state.current} cursor=${move.state.rewindCursor} newPhoto=${move.newPhoto}');
      return result;
    } on GroupedWallpaperBakeException catch (error, stack) {
      groupedWallpaperLog.w('history step failed', error, stack);
      return GroupedWallpaperSyncResult.failed;
    } catch (error, stack) {
      groupedWallpaperLog.e('history step failed', error, stack);
      return GroupedWallpaperSyncResult.failed;
    }
  }

  /// Drops the older records after a queued frame can no longer be shown.
  ///
  /// Without the write the bar would keep offering a "previous" the engine
  /// refuses, which is exactly the dead button this walk exists to avoid.
  Future<void> _trimRewind(GroupedWallpaperStateStore store, GroupedWallpaperState state, {int? entryId}) async {
    var keep = state.rewind.take(state.rewindCursor + 1).toList(growable: false);
    if (entryId != null) keep = keep.where((record) => record.entryId != entryId).toList(growable: false);
    if (keep.length == state.rewind.length) return;
    // A generation bump makes the renderer drop the in-memory neighbour it can no
    // longer show, instead of promoting a dead record on the next tap.
    await store.writeState(state.copyWith(generation: state.generation + 1, rewind: keep, rewindCursor: keep.isEmpty ? 0 : keep.length - 1, previous: -1));
    await platform.reload();
    await platform.refreshNotification();
  }

  /// Moves to the queued slot [target], keeping the frame it replaces as the
  /// opposite neighbour.
  ///
  /// Both directions are one code path: the old frame is always the neighbour of
  /// the new one, and the side that is not [target] is left to [_settle]. The
  /// cursor follows the entry id, so a photo already in the walk moves the cursor
  /// instead of creating a record, exactly like stepping back and forth.
  static ({GroupedWallpaperState state, bool newPhoto})? _moveTo(GroupedWallpaperState state, int target, {required bool navigated}) {
    if (target < 0 || target == state.current) return null;
    final slot = state.slotById(target);
    if (slot == null) return null;
    final back = target == state.previous;
    final index = state.rewind.indexWhere((entry) => entry.entryId == slot.entryId);
    var newPhoto = false;
    var rewind = state.rewind;
    var cursor = state.rewindCursor;
    if (index >= 0) {
      cursor = index;
    } else {
      // A photo the walk has never seen becomes the newest record.
      newPhoto = true;
      final limit = state.historyLimit;
      rewind = limit <= 0
          ? const <GroupedWallpaperRewindEntry>[]
          : [
              GroupedWallpaperRewindEntry(entryId: slot.entryId),
              ...state.rewind.where((entry) => entry.entryId != slot.entryId),
            ].take(limit).toList(growable: false);
      cursor = 0;
    }
    final moved = state.copyWith(
      generation: state.generation + 1,
      status: GroupedWallpaperStatus.ready,
      current: target,
      previous: back ? -1 : state.current,
      next: back ? state.current : -1,
      rewind: rewind,
      rewindCursor: cursor,
      navigated: navigated,
    );
    return (state: moved, newPhoto: newPhoto);
  }

  /// Starts the walk over with a fresh photo as the newest record.
  ///
  /// A group change drops the old group's records; a photo that left the range
  /// keeps them, so "previous" still reaches what the user saw before it went
  /// away.
  Future<GroupedWallpaperSyncResult> _startOver(
    GroupedWallpaperStateStore store,
    GroupedWallpaperPlan plan,
    GroupedWallpaperState? previous, {
    required int total,
    required Size surface,
    required bool scrollEffect,
    Set<int> exclude = const {},
  }) async {
    final sameGroup = previous != null && previous.groupId == plan.group.id;
    final base = previous?.copyWith(
          status: GroupedWallpaperStatus.ready,
          current: -1,
          previous: -1,
          next: -1,
          slots: const [],
          rewind: sameGroup ? previous.rewind : const [],
          rewindCursor: sameGroup ? previous.rewindCursor : 0,
          navigated: false,
        ) ??
        GroupedWallpaperState(
          status: GroupedWallpaperStatus.ready,
          groupId: plan.group.id,
          groupNumber: plan.group.number,
        );
    if (total <= 0) {
      return await _settle(store, plan, base, total: total, surface: surface, scrollEffect: scrollEffect, newPhoto: false, navigated: false);
    }
    // [exclude] holds the entry that just failed to resolve: picking it again
    // would loop between "the photo is gone" and "start over".
    final excluded = <int>{for (final entry in base.recent) entry.entryId, ...exclude};
    for (var attempt = 0; attempt < maxBakeAttempts; attempt++) {
      final pick = await entrySource.pick(
        plan.range,
        ordering: plan.ordering,
        cursor: base.cursor,
        attempt: attempt,
        newestEntryId: base.newestEntryId,
        excludeEntryIds: excluded,
      );
      final entry = pick.entry;
      if (entry == null) break;
      try {
        final slot = await _slotForEntry(store, plan, entry, _nextSlotId(const {}), surface, scrollEffect);
        final limit = plan.historyLimit;
        final rewind = limit <= 0
            ? const <GroupedWallpaperRewindEntry>[]
            : [
                GroupedWallpaperRewindEntry(entryId: entry.id),
                ...base.rewind.where((record) => record.entryId != entry.id),
              ].take(limit).toList(growable: false);
        final seeded = base.copyWith(
          generation: base.generation + 1,
          status: GroupedWallpaperStatus.ready,
          current: slot.id,
          previous: -1,
          next: -1,
          slots: [slot],
          rewind: rewind,
          rewindCursor: 0,
          cursor: pick.offset >= 0 ? pick.offset + 1 : base.cursor,
          count: total,
          newestEntryId: entry.id > base.newestEntryId ? entry.id : base.newestEntryId,
          ordering: plan.ordering,
          bakedAt: now(),
        );
        final newPhoto = previous?.entryId != entry.id || !sameGroup;
        return await _settle(store, plan, seeded, total: total, surface: surface, scrollEffect: scrollEffect, newPhoto: newPhoto, navigated: false);
      } on GroupedWallpaperBakeException catch (error, stack) {
        groupedWallpaperLog.w('start bake failed entry=${entry.id} attempt=$attempt', error, stack);
        excluded.add(entry.id);
      }
    }
    throw const GroupedWallpaperBakeException('no usable photo in the group');
  }

  /// Makes [state] drawable, adopting a promotion the user made while it baked.
  ///
  /// The renderer can promote a neighbour at any time and records it in
  /// `runtime.json`. A bake is long enough for that to happen, so the queue is
  /// settled again from the promoted frame instead of writing a state that would
  /// visibly rewind the wallpaper.
  Future<GroupedWallpaperSyncResult> _settle(
    GroupedWallpaperStateStore store,
    GroupedWallpaperPlan plan,
    GroupedWallpaperState state, {
    required int total,
    required Size surface,
    required bool scrollEffect,
    required bool newPhoto,
    required bool navigated,
  }) async {
    var current = state;
    var recordsNewPhoto = newPhoto;
    var isNavigated = navigated;
    var result = GroupedWallpaperSyncResult.unchanged;
    // A tap during the first bake, then another during the refill: bounded so a
    // very fast double tap cannot spin here.
    for (var attempt = 0; attempt < 3; attempt++) {
      final outcome = await _settleOnce(
        store,
        plan,
        current,
        total: total,
        surface: surface,
        scrollEffect: scrollEffect,
        newPhoto: recordsNewPhoto,
        navigated: isNavigated,
      );
      result = outcome.result;
      final move = outcome.promoted;
      if (move == null) return result;
      current = move.state;
      recordsNewPhoto = move.newPhoto;
      isNavigated = true;
    }
    return result;
  }

  /// Makes [state] drawable: the current frame at the latest layout, plus a baked
  /// neighbour on each side of the cursor.
  ///
  /// At most one frame is baked: the side the move walked away from. Every other
  /// frame comes from the queue or from the cache, which is what makes stepping
  /// through the usage history feel instant.
  Future<({GroupedWallpaperSyncResult result, ({GroupedWallpaperState state, bool newPhoto})? promoted})> _settleOnce(
    GroupedWallpaperStateStore store,
    GroupedWallpaperPlan plan,
    GroupedWallpaperState state, {
    required int total,
    required Size surface,
    required bool scrollEffect,
    required bool newPhoto,
    required bool navigated,
  }) async {
    final layoutStale = _isLayoutStale(state, surface, scrollEffect);
    final slots = <int, GroupedWallpaperSlot>{};
    final usedIds = <int>{};

    var currentSlot = state.currentSlot;
    if (currentSlot == null) {
      final empty = GroupedWallpaperState(
        generation: state.generation + 1,
        status: total <= 0 ? GroupedWallpaperStatus.emptyGroup : GroupedWallpaperStatus.unavailable,
        groupId: plan.group.id,
        groupNumber: plan.group.number,
        groupName: _resolveName(plan.group),
        count: total,
        ordering: plan.ordering,
        gestures: plan.gestures,
        notification: plan.notification,
        surfaceWidth: surface.width.round(),
        surfaceHeight: surface.height.round(),
        scrollEffect: scrollEffect,
        historyLimit: plan.historyLimit,
        switchLocked: _groupSwitchLocked(),
        switchLockedGroupId: wallpaperLockService.groupSwitchLockedGroupId ?? '',
        groups: _groupSnapshot(plan),
        bakedAt: now(),
      );
      await store.clearSlots();
      await store.writeState(empty);
      await platform.reload();
      return (result: total <= 0 ? GroupedWallpaperSyncResult.empty : GroupedWallpaperSyncResult.unchanged, promoted: null);
    }
    final currentEntry = await entrySource.entryById(plan.range, currentSlot.entryId);
    if (currentEntry == null) {
      // The photo is gone: start the group over instead of keeping a frame the
      // range no longer contains.
      final result = await _startOver(store, plan, state, total: total, surface: surface, scrollEffect: scrollEffect, exclude: {currentSlot.entryId});
      return (result: result, promoted: null);
    }
    if (layoutStale || !_slotUsable(store, currentSlot)) {
      currentSlot = await _slotForEntry(store, plan, currentEntry, currentSlot.id, surface, scrollEffect);
    }
    slots[currentSlot.id] = currentSlot;
    usedIds.add(currentSlot.id);

    var rewind = state.rewind;
    var cursor = state.rewindCursor.clamp(0, rewind.isEmpty ? 0 : rewind.length - 1);
    GroupedWallpaperSlot? previousSlot = state.previousSlot;
    GroupedWallpaperSlot? nextSlot = state.nextSlot;

    /// The id a re-baked neighbour takes: its own while it is free, a fresh one
    /// otherwise. Reusing an id the other side already claimed would make both
    /// neighbours the same slot.
    int claimId(GroupedWallpaperSlot? queued) {
      final id = queued?.id;
      if (id != null && !usedIds.contains(id)) return id;
      return _nextSlotId(usedIds);
    }
    var pickCursor = state.cursor;
    var newestEntryId = state.newestEntryId;

    if (cursor + 1 >= rewind.length || cursor + 1 >= plan.historyLimit) {
      previousSlot = null;
    } else {
      final entryId = rewind[cursor + 1].entryId;
      final queued = previousSlot;
      if (queued != null && queued.entryId == entryId && !usedIds.contains(queued.id) && !layoutStale && _slotUsable(store, queued)) {
        slots[queued.id] = queued;
        usedIds.add(queued.id);
      } else {
        final entry = await entrySource.entryById(plan.range, entryId);
        if (entry == null) {
          // It left the range: drop it and everything older, so "previous"
          // stops here instead of failing.
          rewind = rewind.take(cursor + 1).toList(growable: false);
          previousSlot = null;
        } else {
          previousSlot = await _slotForEntry(store, plan, entry, claimId(queued), surface, scrollEffect);
          usedIds.add(previousSlot.id);
          slots[previousSlot.id] = previousSlot;
        }
      }
    }

    if (cursor > 0) {
      final entryId = rewind[cursor - 1].entryId;
      final queued = nextSlot;
      if (queued != null && queued.entryId == entryId && !usedIds.contains(queued.id) && !layoutStale && _slotUsable(store, queued)) {
        slots[queued.id] = queued;
        usedIds.add(queued.id);
      } else {
        final entry = await entrySource.entryById(plan.range, entryId);
        if (entry == null) {
          // The newer record died: it becomes the head, so the next step
          // creates a fresh photo instead of a hole in the walk.
          rewind = rewind.sublist(cursor);
          cursor = 0;
          nextSlot = null;
        } else {
          nextSlot = await _slotForEntry(store, plan, entry, claimId(queued), surface, scrollEffect);
          usedIds.add(nextSlot.id);
          slots[nextSlot.id] = nextSlot;
        }
      }
    }
    if (cursor == 0) {
      // The newest record is on screen, so the forward step creates a new one.
      final queued = nextSlot;
      if (queued != null && !usedIds.contains(queued.id) && !layoutStale && _slotUsable(store, queued)) {
        slots[queued.id] = queued;
        usedIds.add(queued.id);
      } else {
        final picked = await _pickNext(store, plan, state, currentSlot, previousSlot, slots, usedIds, surface: surface, scrollEffect: scrollEffect);
        nextSlot = picked?.slot;
        if (picked != null) {
          pickCursor = picked.cursor;
          slots[picked.slot.id] = picked.slot;
        }
      }
    }

    // A tap can promote one of the neighbours while this run bakes. The renderer
    // writes the runtime with the seed generation, so a matching one that names a
    // queued slot is exactly that: the user moved on, and the queue must follow.
    final runtime = await store.readRuntime();
    if (runtime != null && runtime.matches(state) && runtime.current != state.current && slots.containsKey(runtime.current)) {
      final move = _moveTo(
        state.copyWith(
          current: currentSlot.id,
          previous: previousSlot?.id ?? -1,
          next: nextSlot?.id ?? -1,
          slots: [for (final slot in slots.values) slot],
        ),
        runtime.current,
        navigated: true,
      );
      if (move != null) {
        groupedWallpaperLog.d('queue.adopt during bake current=${runtime.current}');
        return (result: GroupedWallpaperSyncResult.baked, promoted: move);
      }
    }

    if (previousSlot != null && nextSlot != null && previousSlot.id == nextSlot.id) nextSlot = null;
    if (previousSlot != null && previousSlot.id == currentSlot.id) previousSlot = null;
    if (nextSlot != null && nextSlot.id == currentSlot.id) nextSlot = null;

    if (currentSlot.entryId > newestEntryId) newestEntryId = currentSlot.entryId;
    final ordered = <int>{
      if (previousSlot != null) previousSlot.id,
      currentSlot.id,
      if (nextSlot != null) nextSlot.id,
    }.toList();
    final nextState = GroupedWallpaperState(
      generation: state.generation + 1,
      status: GroupedWallpaperStatus.ready,
      groupId: plan.group.id,
      groupNumber: plan.group.number,
      groupName: _resolveName(plan.group),
      count: total,
      current: currentSlot.id,
      previous: previousSlot?.id ?? -1,
      next: nextSlot?.id ?? -1,
      slots: [for (final id in ordered) slots[id]!],
      recent: GroupedWallpaperState.promoteRecent(state.recent, currentSlot, groupId: plan.group.id),
      rewind: rewind,
      rewindCursor: cursor,
      navigated: navigated,
      cursor: pickCursor,
      newestEntryId: newestEntryId,
      ordering: plan.ordering,
      gestures: plan.gestures,
      notification: plan.notification,
      surfaceWidth: surface.width.round(),
      surfaceHeight: surface.height.round(),
      scrollEffect: scrollEffect,
      historyLimit: plan.historyLimit,
      switchLocked: _groupSwitchLocked(),
      switchLockedGroupId: wallpaperLockService.groupSwitchLockedGroupId ?? '',
      groups: _groupSnapshot(plan),
      bakedAt: now(),
    );
    await store.writeState(nextState);
    await store.pruneFrames(keep: _framePaths(nextState), maxFrames: _frameCacheDepth(plan));
    // Frames written before the entry-keyed cache lived under `slots/`.
    await store.pruneSlots(const []);
    if (newPhoto) await _recordShown(plan, currentSlot);
    await platform.reload();
    groupedWallpaperLog.d('queue.settled current=${nextState.current} previous=${nextState.previous} next=${nextState.next} cursor=${nextState.rewindCursor}/${rewind.length} count=$total');
    return (result: GroupedWallpaperSyncResult.baked, promoted: null);
  }

  /// Picks the photo a forward step from the newest record will show.
  ///
  /// It is baked now, so the next double tap or interval is instant. A photo that
  /// already belongs to the walk is not a new record: [_moveTo] then moves the
  /// cursor to it instead.
  Future<({GroupedWallpaperSlot slot, int cursor})?> _pickNext(
    GroupedWallpaperStateStore store,
    GroupedWallpaperPlan plan,
    GroupedWallpaperState state,
    GroupedWallpaperSlot currentSlot,
    GroupedWallpaperSlot? previousSlot,
    Map<int, GroupedWallpaperSlot> slots,
    Set<int> usedIds, {
    required Size surface,
    required bool scrollEffect,
  }) async {
    final excluded = <int>{
      for (final slot in slots.values) slot.entryId,
      currentSlot.entryId,
      if (previousSlot != null) previousSlot.entryId,
      for (final entry in state.recent) entry.entryId,
    };
    var cursor = state.cursor;
    for (var attempt = 0; attempt < maxBakeAttempts; attempt++) {
      final pick = await entrySource.pick(
        plan.range,
        ordering: plan.ordering,
        cursor: cursor,
        attempt: attempt,
        newestEntryId: state.newestEntryId,
        excludeEntryIds: excluded,
      );
      final entry = pick.entry;
      if (entry == null) return null;
      if (pick.offset >= 0) cursor = pick.offset + 1;
      final id = _nextSlotId(usedIds);
      try {
        final slot = await _slotForEntry(store, plan, entry, id, surface, scrollEffect);
        usedIds.add(id);
        return (slot: slot, cursor: cursor);
      } on GroupedWallpaperBakeException catch (error, stack) {
        groupedWallpaperLog.w('neighbour bake failed entry=${entry.id} attempt=$attempt', error, stack);
        excluded.add(entry.id);
      }
    }
    return null;
  }

  /// Every file the state may draw, for the frame cache's eviction.
  static Set<String> _framePaths(GroupedWallpaperState state) => {
        for (final slot in state.slots) ...[
          slot.photo,
          if (slot.effectHome.isNotEmpty) slot.effectHome,
          if (slot.effectLock.isNotEmpty) slot.effectLock,
        ],
      };

  /// How many frames the cache keeps, so stepping back stays instant.
  ///
  /// Bounded so a long history does not turn into hundreds of megabytes of PNGs;
  /// a frame beyond the cache is baked once more when it is reached.
  static int _frameCacheDepth(GroupedWallpaperPlan plan) => math.max(6, math.min(plan.historyLimit, 24));

  /// Whether a slot's files are all still on disk.
  static bool _slotUsable(GroupedWallpaperStateStore store, GroupedWallpaperSlot slot) {
    if (store.slotPhotoOf(slot) == null) return false;
    if (slot.effectHome.isNotEmpty && !store.effectPhotoExists(slot.effectHome)) return false;
    if (slot.effectLock.isNotEmpty && !store.effectPhotoExists(slot.effectLock)) return false;
    return true;
  }

  /// The frame of [entry] for slot [id], from the cache when it was baked before.
  ///
  /// The cache key carries the target size and the effects, so a hit is exactly
  /// the frame this slot would have produced: stepping back through the usage
  /// history costs a file reference instead of a decode, an effect pass and an
  /// encode.
  Future<GroupedWallpaperSlot> _slotForEntry(GroupedWallpaperStateStore store, GroupedWallpaperPlan plan, AvesEntry entry, int id, Size surface, bool scrollEffect) async {
    final target = scrollEffect ? _scrollTarget(surface, entry) : surface;
    final key = _frameKey(plan, target, scrollEffect);
    final title = entry.bestTitle ?? '';
    final cached = store.cachedFrame(entry.id, key);
    if (cached != null) {
      return GroupedWallpaperSlot(
        id: id,
        entryId: entry.id,
        uri: entry.uri,
        title: title,
        photo: cached.photo,
        effectHome: cached.effectHome,
        effectLock: cached.effectLock,
        width: cached.width,
        height: cached.height,
        darkness: cached.darkness,
      );
    }
    final bake = await baker.bake(
      entry: entry,
      targetSize: target,
      home: plan.effects.home,
      lock: plan.effects.effectiveLock,
    );
    final photo = await store.writeFramePhoto(entry.id, key, bake.sharpPng);
    // An identity effect is the sharp frame: leaving the path empty makes the
    // renderer fall back to it instead of storing a second copy of the PNG.
    final effectHome = identical(bake.effectsHomePng, bake.sharpPng)
        ? ''
        : await store.writeFramePhoto(entry.id, key, bake.effectsHomePng, name: GroupedWallpaperStateStore.slotEffectHomeFileName);
    final effectLock = identical(bake.effectsLockPng, bake.sharpPng)
        ? ''
        : identical(bake.effectsLockPng, bake.effectsHomePng)
            ? effectHome
            : await store.writeFramePhoto(entry.id, key, bake.effectsLockPng, name: GroupedWallpaperStateStore.slotEffectLockFileName);
    final width = bake.size.width.round();
    final height = bake.size.height.round();
    await store.writeFrameMeta(entry.id, key, width: width, height: height, darkness: bake.darkness, title: title, uri: entry.uri);
    return GroupedWallpaperSlot(
      id: id,
      entryId: entry.id,
      uri: entry.uri,
      title: title,
      photo: photo,
      effectHome: effectHome,
      effectLock: effectLock,
      width: width,
      height: height,
      darkness: bake.darkness,
    );
  }

  /// Cache key of one photo at one layout.
  ///
  /// The surface and the effects decide every pixel of a baked frame, so a change
  /// to either must miss the cache instead of showing the previous rendering.
  static String _frameKey(GroupedWallpaperPlan plan, Size target, bool scrollEffect) {
    final effects = jsonEncode([
      plan.effects.home.toJsonMap(),
      plan.effects.effectiveLock.toJsonMap(),
      scrollEffect,
    ]);
    return '${target.width.round()}x${target.height.round()}-${_fingerprint(effects)}';
  }

  /// A short, stable hash for a directory name.
  ///
  /// `String.hashCode` is randomized per process, so it cannot name a file.
  static String _fingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// The smallest slot id not in use, so a freed slot is recycled instead of
  /// growing the directory forever.
  static int _nextSlotId(Set<int> used) {
    for (var id = 0; ; id++) {
      if (!used.contains(id)) return id;
    }
  }

  /// Adopts the slot the native renderer promoted to, when the runtime still
  /// belongs to the state we know about.
  ///
  /// The renderer only ever promotes one of the two queued neighbours, so the
  /// move and its cursor are exactly what a page tap would have done: stepping
  /// back and forth through the usage records, and creating a new record only
  /// from the newest one.
  static ({GroupedWallpaperState state, bool newPhoto})? _adoptRuntime(GroupedWallpaperState? state, GroupedWallpaperRuntime? runtime) {
    if (state == null || runtime == null) return null;
    if (!runtime.matches(state)) return null;
    return _moveTo(state, runtime.current, navigated: true);
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

  /// Whether frames should keep the photo's whole width for the launcher to pan.
  ///
  /// The switch is the user's, but a launcher that never pans (`xOffsetStep` 0)
  /// has nothing to pan with, so a wide frame there would only crop the sides. An
  /// unknown step means no offset callback arrived yet: follow the switch.
  Future<bool> _effectiveScrollEffect(GroupedWallpaperPlan plan) async {
    if (!plan.effects.homeScrollEffect) return false;
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

  /// Whether [state] already has the neighbours its cursor implies, on disk.
  ///
  /// A missing side normally means a bake is pending; the caller then settles
  /// instead of writing a state the bar would have to refuse.
  Future<bool> _isQueueReady(GroupedWallpaperStateStore store, int total, GroupedWallpaperState state) async {
    if (state.status == GroupedWallpaperStatus.emptyGroup && total == 0) return true;
    if (state.status != GroupedWallpaperStatus.ready || !state.hasPhoto) return false;
    final wantsOlder = state.rewindCursor + 1 < state.rewind.length && state.rewindCursor + 1 < state.historyLimit;
    if (wantsOlder != (state.previous >= 0)) return false;
    if (state.next < 0) return false;
    // Both sides must name different slots: a file that queues one id twice
    // describes no move at all.
    if (state.previous >= 0 && state.previous == state.next) return false;
    if (state.previous == state.current || state.next == state.current) return false;
    for (final slot in state.slots) {
      if (!_slotUsable(store, slot)) return false;
    }
    return true;
  }

  /// Records a photo the walk has never seen as the newest usage record.
  ///
  /// Stepping back and forth through the records does not call this: browsing is
  /// not "using" a photo again, and rewriting `usedAt` on every step would reorder
  /// the history the walk is based on.
  Future<void> _recordShown(GroupedWallpaperPlan plan, GroupedWallpaperSlot slot) async {
    if (slot.entryId <= 0) return;
    if (plan.historyLimit <= 0) return;
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
        ? previous.copyWith(
            generation: previous.generation + 1,
            status: GroupedWallpaperStatus.locked,
            historyLimit: plan.historyLimit,
            switchLocked: _groupSwitchLocked(),
            switchLockedGroupId: wallpaperLockService.groupSwitchLockedGroupId ?? '',
            groups: _groupSnapshot(plan),
          )
        : GroupedWallpaperState(
            generation: 1,
            status: GroupedWallpaperStatus.locked,
            groupId: plan.group.id,
            groupNumber: plan.group.number,
            groupName: _resolveName(plan.group),
            ordering: plan.ordering,
            gestures: plan.gestures,
            notification: plan.notification,
            historyLimit: plan.historyLimit,
            switchLocked: _groupSwitchLocked(),
            switchLockedGroupId: wallpaperLockService.groupSwitchLockedGroupId ?? '',
            groups: _groupSnapshot(plan),
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
              notification: plan.notification,
              historyLimit: plan.historyLimit,
              switchLocked: _groupSwitchLocked(),
              switchLockedGroupId: wallpaperLockService.groupSwitchLockedGroupId ?? '',
              groups: _groupSnapshot(plan),
              bakedAt: now(),
            )
          : GroupedWallpaperState(
              generation: (previous?.generation ?? 0) + 1,
              status: GroupedWallpaperStatus.unavailable,
              groupId: previous?.groupId ?? '',
              groupNumber: previous?.groupNumber ?? 0,
              groupName: previous?.groupName ?? '',
              gestures: previous?.gestures ?? const GroupedWallpaperGestures(),
              notification: previous?.notification ?? true,
              historyLimit: previous?.historyLimit ?? GroupedWallpaperHistoryLimit.defaultLimit,
              switchLocked: _groupSwitchLocked(),
              switchLockedGroupId: wallpaperLockService.groupSwitchLockedGroupId ?? '',
              groups: previous?.groups ?? const [],
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
    final seconds = plan.disabled || plan.isNone ? 0 : plan.interval.seconds;
    await platform.scheduleAutoAdvance(seconds);
  }

  /// Restarts the interval after an explicit step.
  ///
  /// The scheduler keeps an unchanged interval's pending run on purpose, but a
  /// step is the user changing the wallpaper by hand, so the countdown starts
  /// over instead of firing right after it.
  Future<void> _restartAutoAdvance(GroupedWallpaperPlan plan) async {
    final seconds = plan.disabled || plan.isNone ? 0 : plan.interval.seconds;
    await platform.restartAutoAdvance(seconds);
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

  /// The rotation the bar switches through, with names it can display.
  ///
  /// Resolved on write so the native side never has to know an `@arbKey` or the
  /// app language: the bar keeps working while the app is not running.
  List<GroupedWallpaperGroup> _groupSnapshot(GroupedWallpaperPlan plan) => [
        for (final group in plan.groups) GroupedWallpaperGroup(id: group.id, number: group.number, name: _resolveName(group)),
      ];

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
