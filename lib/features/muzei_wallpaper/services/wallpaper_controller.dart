import 'dart:async';
import 'dart:io';

import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_bake.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_gestures.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_prefetch_setting.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_state.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_baker.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_source_repository.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Drives the live-wallpaper pipeline:
/// database query -> bake -> slot files -> `state.json` -> native renderer.
///
/// It is the only writer of `state.json`; the native side writes `runtime.json`
/// after it loads a slot. Everything platform-facing is injected, so the whole
/// state machine is testable on the host without channels or a device.
class WallpaperController extends ChangeNotifier {
  /// Bake retries before the controller gives up on an advance.
  ///
  /// Each retry shifts the source offset, so a single corrupt photo cannot pin
  /// the wallpaper to itself.
  static const int maxBakeAttempts = 5;

  /// Fixed slot ids. The queue is `current` → `next` → `next2`: the renderer
  /// shows `current`, and a tap promotes the baked slots without waiting for a
  /// decode.
  ///
  /// Unlike Muzei, which blurs at draw time and can advance instantly, this port
  /// has to bake ahead, so a tap can outrun the refill. One artwork ahead keeps
  /// every tap honest but the second one waits for a bake; the
  /// `muzei_wallpaper_prefetch_ahead` setting (Meta Settings, default on) adds
  /// the [thirdSlotId] slot so the first two taps are instant, at the cost of
  /// one more baked artwork on disk and in every effect rebake. The renderer
  /// buffers taps beyond that (`AdvanceRequestQueue`) and this controller
  /// refills the freed slots right away, including from a headless background
  /// run.
  static const int firstSlotId = 0;
  static const int secondSlotId = 1;
  static const int thirdSlotId = 2;

  /// All slot ids, deepest last.
  static const List<int> slotIds = [firstSlotId, secondSlotId, thirdSlotId];

  final WallpaperPrefs prefs;
  final WallpaperSourceRepository repository;
  final WallpaperBaker baker;
  final WallpaperStateStore store;
  final WallpaperBridge? bridge;
  final Future<Size> Function() targetSize;

  /// Reads the two-ahead opt-in. Injected so tests can drive the queue depth
  /// without touching the app settings store.
  final bool Function() prefetchAhead;

  WallpaperState _state = const WallpaperState();
  WallpaperSourceResolution? _resolution;
  bool _initialized = false;
  bool _busy = false;
  bool _baking = false;
  bool _serviceActive = false;
  bool _disposed = false;
  String? _error;
  int _cursor = 0;
  WallpaperEffectsConfig? _pendingEffects;
  int _effectsSequence = 0;
  Future<void>? _initFuture;
  Future<void>? _advanceFuture;
  Future<void>? _prefetchFuture;

  new({
    required this.prefs,
    required this.repository,
    required this.baker,
    required this.store,
    this.bridge,
    Future<Size> Function()? targetSize,
    bool Function()? prefetchAhead,
  }) : prefetchAhead = prefetchAhead ?? _readPrefetchSetting,
       targetSize = targetSize ?? _defaultTargetSize;

  WallpaperState get state => _state;

  WallpaperSlot? get current => _state.currentSlot;

  WallpaperSlot? get next => _state.nextSlot;

  WallpaperSlot? get next2 => _state.next2Slot;

  WallpaperSourceResolution? get resolution => _resolution;

  bool get initialized => _initialized;

  bool get busy => _busy;

  bool get baking => _baking;

  bool get serviceActive => _serviceActive;

  bool get hasContent => current != null;

  String? get error => _error;

  File? get currentFile => _slotFile(current);

  File? get nextFile => _slotFile(next);

  /// Resolves the sharp file of [slot] from the path recorded in the state.
  ///
  /// This is the same relative path the native renderer reads, so the preview
  /// and the desktop can never point at different files.
  File? _slotFile(WallpaperSlot? slot) {
    final relative = slot?.artwork.files.sharp;
    if (slot == null || relative == null || relative.isEmpty) return null;
    return store.resolveSlotPath(relative);
  }

  Future<void> init() => _initFuture ??= _doInit();

  /// Waits for the current advance and prefetch, if any.
  ///
  /// The foreground page does not need it; tests and the background worker use
  /// it to observe a settled state.
  Future<void> get idle async {
    while (true) {
      final advance = _advanceFuture;
      final prefetch = _prefetchFuture;
      if (advance == null && prefetch == null) return;
      await Future.wait([?advance, ?prefetch]);
    }
  }

  Future<void> _doInit() async {
    try {
      await prefs.init();
      await store.ensureLayout();
      _state = await store.readState() ?? const WallpaperState();
      _cursor = prefs.currentIndex;

      final scope = prefs.scope;
      _resolution = scope.isConfigured ? await repository.resolve(scope) : WallpaperSourceResolution.missing;

      if (_state.sourceRevision != scope.revision) {
        await _discardSlots();
        _state = WallpaperState(
          // Keep the generation monotonic even when the source changed while
          // the process was dead.
          generation: _state.generation,
          sourceRevision: scope.revision,
          effects: prefs.effects,
          gestures: prefs.gestures,
        );
      } else {
        await _validateSlots();
        await _adoptRuntime(await store.readRuntime());
        // Settings may have changed while the app was closed; they are cheap
        // to carry over and must reach the native side before the first draw.
        _state = _state.copyWith(
          sourceRevision: scope.revision,
          effects: prefs.effects,
          gestures: prefs.gestures,
        );
      }

      if (_state.currentSlot != null) {
        // The persisted index is the position of the current artwork; the next
        // in-order pick starts after it.
        _cursor = prefs.currentIndex + 1;
      }
    } catch (error, stack) {
      _error = error.toString();
      wallpaperLog.e('failed to initialize the wallpaper controller', error, stack);
    } finally {
      _initialized = true;
      _notify();
    }

    // The persisted schedule is native state; a reinstall or a force-stop can
    // lose it, so reconcile it whenever the page opens.
    unawaited(_scheduleAutoAdvance());

    await _applyPrefetchDepth();

    if (_state.currentSlot == null) {
      await advance();
    } else {
      await refreshServiceActive();
      unawaited(prefetch());
    }

    wallpaperLog.i(
      'controller.init generation=${_state.generation} current=${_state.current} '
      'next=${_state.next} next2=${_state.next2} depth=$_prefetchDepth '
      'status=${_resolution?.status.name}',
    );
  }

  /// Promotes the prefetched artwork, or bakes a new one when no prefetch is
  /// ready.
  ///
  /// Promotion is deliberately synchronous with the state write: `next` is
  /// already on disk, so a launcher tap must not wait for another decode.
  Future<void> advance({bool prefetchOnly = false}) {
    final existing = _advanceFuture;
    if (existing != null) return existing;
    final future = _doAdvance(prefetchOnly: prefetchOnly);
    _advanceFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_advanceFuture, future)) _advanceFuture = null;
      }),
    );
    return future;
  }

  Future<void> _doAdvance({required bool prefetchOnly}) async {
    if (!_initialized) await init();
    if (_busy) return;

    _busy = true;
    _error = null;
    _notify();
    // A prefetch started here must run after the lock is released; starting it
    // inside the body would leave it baking without the lock.
    var prefetchAfter = false;
    try {
      await store.runExclusive(() async {
        // A background refill may have advanced while this isolate was idle;
        // merge its state before choosing a slot.
        await _refreshFromDisk();
        final scope = prefs.scope;
        _resolution = scope.isConfigured ? await repository.resolve(scope) : WallpaperSourceResolution.missing;

        if (!_resolution!.isReady) {
          await _applyUnavailableSource(scope);
          return;
        }

        if (!prefetchOnly) {
          // A prefetch may be baking the very slot this advance wants to
          // promote; let it finish instead of decoding the artwork twice.
          final pendingPrefetch = _prefetchFuture;
          if (_state.nextSlot == null && pendingPrefetch != null) {
            await pendingPrefetch;
          }

          final next = _state.nextSlot;
          if (next != null && _state.sourceRevision == scope.revision) {
            // Shift the queue: the deeper spare becomes promotable, and the slot
            // the old current occupied is freed for the refill.
            final deeper = _state.next2Slot;
            final keep = deeper != null && deeper.id != next.id ? deeper : null;
            await _commit(
              _state.copyWith(
                generation: _state.generation + 1,
                current: next.id,
                next: keep?.id ?? -1,
                next2: -1,
                slots: [next, ?keep],
                sourceRevision: scope.revision,
                effects: prefs.effects,
                gestures: prefs.gestures,
              ),
            );
            wallpaperLog.i('advance.promote slot=${next.id} entry=${next.artwork.entryId} next=${keep?.id ?? -1}');
            prefetchAfter = true;
            return;
          }
        }

        final slotId = _freeSlotId(requireCurrent: prefetchOnly);
        if (slotId == null) return;
        final slot = await _bakeSlot(scope, _resolution!, slotId);
        if (slot == null) {
          _error = 'failed to bake a wallpaper from the current source';
          return;
        }

        final newState = prefetchOnly
            ? _state.copyWith(
                generation: _state.generation + 1,
                next: slot.id,
                slots: _withSlot(slot),
                sourceRevision: scope.revision,
                effects: prefs.effects,
                gestures: prefs.gestures,
              )
            : _state.copyWith(
                generation: _state.generation + 1,
                current: slot.id,
                next: -1,
                next2: -1,
                slots: [slot],
                sourceRevision: scope.revision,
                effects: prefs.effects,
                gestures: prefs.gestures,
              );
        await _commit(newState);
        wallpaperLog.i('advance.bake slot=${slot.id} entry=${slot.artwork.entryId}');
        if (!prefetchOnly) prefetchAfter = true;
      });
    } catch (error, stack) {
      _error = error.toString();
      wallpaperLog.e('advance failed', error, stack);
    } finally {
      _busy = false;
      _notify();
    }
    if (prefetchAfter) unawaited(prefetch());
  }

  /// Bakes the artwork after the current one into the free slot.
  ///
  /// Failures are non-fatal: the current wallpaper stays, and the next advance
  /// retries from the shifted cursor.
  Future<void> prefetch() {
    final existing = _prefetchFuture;
    if (existing != null) return existing;
    final future = _doPrefetch();
    _prefetchFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_prefetchFuture, future)) _prefetchFuture = null;
      }),
    );
    return future;
  }

  Future<void> _doPrefetch() async {
    if (!_initialized) return;
    final scope = prefs.scope;
    if (!scope.isConfigured) return;

    try {
      await store.runExclusive(() async {
        // Adopt whatever the background refill committed before deciding that
        // a slot is still free to bake.
        await _refreshFromDisk();
        if (_state.currentSlot == null) return;
        final resolution = _resolution ?? await repository.resolve(scope);
        if (!resolution.isReady) return;

        // Fill the queue in promotion order: `next` first, then the deeper
        // spare, so a half-finished prefetch still leaves the next tap served.
        //
        // A tap can land while a spare is encoding: the renderer promotes the
        // deeper slot and records it in `runtime.json` without touching the
        // state, so the bake re-reads the runtime before committing and adopts
        // it. Otherwise the commit would rewind the wallpaper to the artwork the
        // previous tap promoted.
        var aborted = 0;
        while (!_disposed) {
          final missing = _missingSlotId();
          if (missing == null) return;
          final revision = _state.sourceRevision;

          final slot = await _bakeSlot(scope, resolution, missing);
          if (slot == null) return;
          if (_state.sourceRevision != revision || _state.currentSlot == null) return;
          await _adoptRuntime(await store.readRuntime());

          final fillNext = _state.nextSlot == null;
          if (!fillNext && _state.next2Slot != null) {
            // The queue filled up while this bake ran; the baked files stay in
            // the slot and are overwritten by the next bake into it.
            if (++aborted >= maxBakeAttempts) return;
            continue;
          }
          aborted = 0;
          await _commit(
            _state.copyWith(
              generation: _state.generation + 1,
              next: fillNext ? slot.id : _state.next,
              next2: fillNext ? _state.next2 : slot.id,
              slots: _withSlot(slot),
              sourceRevision: scope.revision,
              effects: prefs.effects,
              gestures: prefs.gestures,
            ),
          );
          wallpaperLog.i('prefetch.done slot=${slot.id} level=${fillNext ? 1 : 2} entry=${slot.artwork.entryId}');
        }
      });
    } catch (error, stack) {
      wallpaperLog.w('prefetch failed', error, stack);
    }
  }

  /// Drops the deeper slot when the two-ahead option is off.
  ///
  /// The flag is read when the controller starts, so turning it off must not
  /// leave a `next2` the renderer would still promote from deleted files. It is
  /// a no-op while the option stays on.
  Future<void> _applyPrefetchDepth() async {
    if (_prefetchDepth > 1) return;
    try {
      await store.runExclusive(() async {
        await _refreshFromDisk();
        final spare = _state.next2Slot;
        if (spare == null) return;
        await store.deleteSlot(spare.id);
        await _commit(
          _state.copyWith(
            generation: _state.generation + 1,
            next2: -1,
            slots: _state.slots.where((slot) => slot.id != spare.id).toList(),
          ),
        );
        wallpaperLog.i('prefetch.depth spare dropped slot=${spare.id}');
      });
    } catch (error, stack) {
      wallpaperLog.w('failed to drop the spare slot', error, stack);
    }
  }

  /// Picks and bakes into [slotId], retrying other offsets on decode failure.
  Future<WallpaperSlot?> _bakeSlot(
    WallpaperSourceScope scope,
    WallpaperSourceResolution resolution,
    int slotId,
  ) async {
    if (resolution.total <= 0) return null;
    final pick = await repository.pick(
      scope,
      ordering: prefs.autoAdvance.ordering,
      cursor: _cursor,
    );
    if (!pick.hasEntry) return null;

    final size = await targetSize();
    final total = pick.total;
    var offset = pick.offset;
    for (var attempt = 0; attempt < maxBakeAttempts; attempt++) {
      final entry = attempt == 0 && pick.entry != null
          ? pick.entry!
          : await repository.pickAt(scope, total: total, offset: offset + attempt);
      if (entry == null) continue;
      try {
        final bake = await baker.bake(
          entry: entry,
          targetSize: size,
          home: prefs.effects.home,
          lock: prefs.effects.effectiveLock,
        );
        final slot = await _writeSlot(slotId, entry, bake);
        _cursor = offset + attempt + 1;
        await prefs.setCurrentIndex(_normalize(offset + attempt, total));
        return slot;
      } on WallpaperBakeException catch (error, stack) {
        wallpaperLog.w('bake failed entry=${entry.id} slot=$slotId attempt=$attempt', error, stack);
      }
    }
    wallpaperLog.w('bake gave up after $maxBakeAttempts attempts slot=$slotId');
    return null;
  }

  Future<WallpaperSlot> _writeSlot(int slotId, AvesEntry entry, WallpaperBake bake) async {
    await store.writeSlotBytes(slotId, WallpaperSlotFiles.sharpName, bake.sharpPng);
    await store.writeSlotBytes(slotId, WallpaperSlotFiles.effectsHomeName, bake.effectsHomePng);
    await store.writeSlotBytes(slotId, WallpaperSlotFiles.effectsLockName, bake.effectsLockPng);
    final artwork = WallpaperArtwork(
      entryId: entry.id,
      uri: entry.uri,
      title: entry.bestTitle,
      byline: _byline(entry),
      dateMillis: entry.bestDate?.millisecondsSinceEpoch,
      files: WallpaperSlotFiles(
        sharp: WallpaperStateStore.relativeSlotFile(slotId, WallpaperSlotFiles.sharpName),
        effectsHome: WallpaperStateStore.relativeSlotFile(slotId, WallpaperSlotFiles.effectsHomeName),
        effectsLock: WallpaperStateStore.relativeSlotFile(slotId, WallpaperSlotFiles.effectsLockName),
      ),
    );
    await store.writeSlotArtwork(slotId, artwork);
    return WallpaperSlot(id: slotId, artwork: artwork);
  }

  /// Applies a source change: old slots are unusable and are dropped first.
  Future<void> setScope(WallpaperSourceScope scope) async {
    if (!scope.isConfigured) {
      _error = 'the source is not configured';
      _notify();
      return;
    }
    if (!_initialized) await init();
    await idle;
    if (_disposed) return;
    await prefs.setSourceScope(scope);
    _cursor = 0;
    await prefs.setCurrentIndex(0);
    await _discardSlots();
    _state = WallpaperState(
      generation: _state.generation + 1,
      sourceRevision: scope.revision,
      effects: prefs.effects,
      gestures: prefs.gestures,
    );
    await store.writeState(_state);
    await store.writeRuntime(WallpaperRuntime.empty);
    await _reloadRenderer();
    _resolution = await repository.resolve(scope);
    _notify();
    await advance();
  }

  Future<void> setSingle(int? entryId) {
    final scope = prefs.scope.copyWith(
      kind: WallpaperSourceKind.single,
      singleEntryId: entryId,
      clearSingleEntryId: entryId == null,
    );
    return setScope(scope);
  }

  /// Rebakes only the effect images from the existing `sharp.png` files.
  ///
  /// Slider changes arrive faster than a rebake, so a change that lands while
  /// another is baking is folded into the running loop instead of being
  /// dropped: the last value the user picked always reaches the baked images.
  Future<void> setEffects(WallpaperEffectsConfig effects) async {
    final sequence = ++_effectsSequence;
    await prefs.setEffects(effects);
    // A newer change overtook this one while the preferences were being stored;
    // that call owns the bake.
    if (sequence != _effectsSequence) return;
    _pendingEffects = effects;
    if (_baking) return;

    _baking = true;
    _error = null;
    _notify();
    try {
      await idle;
      while (_pendingEffects != null && !_disposed) {
        final target = _pendingEffects!;
        _pendingEffects = null;
        final rebaked = await _rebakeEffects(target);
        if (rebaked) {
          await _commit(_state.copyWith(generation: _state.generation + 1, effects: target));
        } else {
          _state = _state.copyWith(effects: target);
        }
      }
    } finally {
      _baking = false;
      _notify();
    }
  }

  /// Rewrites both effect images of every slot; returns whether any was written.
  Future<bool> _rebakeEffects(WallpaperEffectsConfig effects) async {
    var rebaked = false;
    for (final slot in _state.slots) {
      final sharpPath = slot.artwork.files.sharp;
      if (sharpPath.isEmpty) continue;
      final sharpFile = store.resolveSlotPath(sharpPath);
      if (!await sharpFile.exists()) continue;
      try {
        final bake = await baker.bakeEffects(
          sharpPng: await sharpFile.readAsBytes(),
          home: effects.home,
          lock: effects.effectiveLock,
        );
        await store.writeSlotBytes(slot.id, WallpaperSlotFiles.effectsHomeName, bake.effectsHomePng);
        await store.writeSlotBytes(slot.id, WallpaperSlotFiles.effectsLockName, bake.effectsLockPng);
        rebaked = true;
      } on WallpaperBakeException catch (error, stack) {
        wallpaperLog.w('effects rebake failed slot=${slot.id}', error, stack);
      }
    }
    return rebaked;
  }

  Future<void> setGestures(WallpaperGestures gestures) async {
    await prefs.setGestures(gestures);
    if (_state.gestures == gestures) return;
    await _commit(_state.copyWith(generation: _state.generation + 1, gestures: gestures));
  }

  /// Persists the auto-advance contract and hands the schedule to the native
  /// worker, which is the only component that survives the page.
  Future<void> setAutoAdvance(WallpaperAutoAdvance value) async {
    await prefs.setAutoAdvance(value);
    await _scheduleAutoAdvance();
    _notify();
  }

  Future<void> _scheduleAutoAdvance() async {
    try {
      await bridge?.scheduleAutoAdvance(prefs.autoAdvance.interval.seconds);
    } catch (error, stack) {
      // Auto-advance is an enhancement; a platform that refuses to schedule
      // must never break the wallpaper page.
      wallpaperLog.w('auto-advance scheduling failed', error, stack);
    }
  }

  Future<bool> openChooser() async {
    final opened = await bridge?.openChooser() ?? false;
    await refreshServiceActive();
    return opened;
  }

  Future<void> refreshServiceActive() async {
    final bridge = this.bridge;
    if (bridge == null) return;
    final active = await bridge.isActive();
    if (active != _serviceActive) {
      _serviceActive = active;
      _notify();
      // Applying the wallpaper is the moment auto-advance starts mattering; the
      // native scheduler is idempotent, so re-checking is cheap.
      if (active) unawaited(_scheduleAutoAdvance());
    }
  }

  /// Adopts a slot the renderer advanced to on its own, then refills the slot it
  /// left behind.
  ///
  /// Also used after a background run: the state it committed is newer than the
  /// cached one, and the preview must catch up without waiting for a restart.
  Future<void> syncRuntime() async {
    if (!_initialized) await init();
    var prefetchAfter = false;
    await store.runExclusive(() async {
      await _refreshFromDisk();
      await _adoptRuntime(await store.readRuntime());
      prefetchAfter = _state.currentSlot != null && _missingSlotId() != null;
    });
    await refreshServiceActive();
    if (prefetchAfter) unawaited(prefetch());
  }

  /// Merges an older in-memory state with a newer `state.json`.
  ///
  /// The background refill writes the same file from another isolate; a cached
  /// state would otherwise bake into the slot that run just filled.
  Future<void> _refreshFromDisk() async {
    final stored = await store.readState();
    if (stored == null || stored.generation <= _state.generation) return;
    _state = stored;
    // The in-order cursor lives in SharedPreferences, whose value is cached per
    // isolate; random ordering (the default) does not read it, so a stale value
    // is cosmetic here.
    _cursor = prefs.currentIndex + 1;
    await _adoptRuntime(await store.readRuntime());
    wallpaperLog.i('state.reload generation=${_state.generation} current=${_state.current} next=${_state.next} next2=${_state.next2}');
    _notify();
  }

  Future<AvesEntry?> loadCurrentEntry() async {
    final slot = _state.currentSlot;
    if (slot == null) return null;
    return repository.entryById(slot.artwork.entryId);
  }

  /// Loads one entry by id, so the source editor can label a single choice that
  /// is not the artwork currently on the wallpaper.
  Future<AvesEntry?> loadEntry(int id) => repository.entryById(id);

  Future<void> _adoptRuntime(WallpaperRuntime? runtime) async {
    if (runtime == null || !runtime.matches(_state)) return;
    final runtimeCurrent = _state.slotById(runtime.current);
    if (runtimeCurrent == null) return;
    final runtimeNext = _state.slotById(runtime.next);
    final nextId = runtimeNext != null && runtimeNext.id != runtimeCurrent.id ? runtimeNext.id : -1;
    // Nothing advanced: the deeper spare must survive, and the runtime cannot
    // describe it (it only carries one promotable slot).
    if (runtimeCurrent.id == _state.current && nextId == _state.next) return;
    // A runtime promotion consumes the deeper spare it moved past; the refill
    // rebuilds the queue from here.
    _state = _state.copyWith(
      current: runtimeCurrent.id,
      next: nextId,
      next2: -1,
      slots: [runtimeCurrent, if (runtimeNext != null && nextId >= 0) runtimeNext],
    );
    // Keep the runtime generation: the renderer is already showing this slot,
    // and a prefetch rewrites the state with the next generation.
    await store.writeState(_state);
    wallpaperLog.i('runtime.adopt current=${_state.current} next=${_state.next}');
    _notify();
  }

  Future<void> _validateSlots() async {
    for (final id in _state.queue.toSet()) {
      final slot = _state.slotById(id);
      if (slot == null) continue;
      if (await repository.entryById(slot.artwork.entryId) != null) continue;
      wallpaperLog.w('slot entry is gone id=${slot.artwork.entryId} slot=$id');
      await store.deleteSlot(id);
      _state = _state.copyWith(
        current: _state.current == id ? -1 : _state.current,
        next: _state.next == id ? -1 : _state.next,
        next2: _state.next2 == id ? -1 : _state.next2,
        slots: _state.slots.where((existing) => existing.id != id).toList(),
      );
    }
  }

  Future<void> _applyUnavailableSource(WallpaperSourceScope scope) async {
    final current = _state.currentSlot;
    for (final slot in _state.slots) {
      if (slot.id != current?.id) await store.deleteSlot(slot.id);
    }
    await _commit(
      _state.copyWith(
        generation: _state.generation + 1,
        current: current?.id ?? -1,
        next: -1,
        next2: -1,
        slots: current != null ? [current] : <WallpaperSlot>[],
        sourceRevision: scope.revision,
        effects: prefs.effects,
        gestures: prefs.gestures,
      ),
    );
    wallpaperLog.i('advance.source ${_resolution?.status.name}');
  }

  Future<void> _commit(WallpaperState state) async {
    _state = state;
    await store.writeState(state);
    // The runtime describes the previous generation; clearing it prevents a
    // stale slot from being adopted before the renderer reloads.
    await store.writeRuntime(WallpaperRuntime.empty);
    _notify();
    await _reloadRenderer();
  }

  Future<void> _reloadRenderer() async {
    try {
      await bridge?.reload();
    } catch (error, stack) {
      wallpaperLog.w('renderer reload failed', error, stack);
    }
  }

  Future<void> _discardSlots() async {
    // Every fixed id, not just the referenced ones: a slot left behind by a
    // deeper prefetch would otherwise never be reused after the option is
    // turned off.
    for (final id in slotIds) {
      await store.deleteSlot(id);
    }
  }

  /// How many artworks to keep baked ahead of [current].
  int get _prefetchDepth => prefetchAhead() ? 2 : 1;

  /// The free slot to bake for the next queue level, or null when the queue is
  /// already as deep as the setting allows.
  int? _missingSlotId() {
    if (_state.currentSlot == null) return null;
    if (_state.nextSlot == null) return _freeSlotId();
    if (_prefetchDepth >= 2 && _state.next2Slot == null) return _freeSlotId();
    return null;
  }

  /// The smallest slot id the queue does not reference.
  ///
  /// The browsable ids follow the prefetch depth, so turning the deeper queue
  /// off keeps reusing the original two slots.
  int? _freeSlotId({bool requireCurrent = false}) {
    if (requireCurrent && _state.currentSlot == null) return null;
    final used = {_state.current, _state.next, _state.next2};
    for (var id = firstSlotId; id <= _prefetchDepth; id++) {
      if (!used.contains(id)) return id;
    }
    return null;
  }

  List<WallpaperSlot> _withSlot(WallpaperSlot slot) {
    final slots = _state.slots.where((existing) => existing.id != slot.id).toList()..add(slot);
    slots.sort((a, b) => a.id.compareTo(b.id));
    return slots;
  }

  static int _normalize(int value, int total) => total <= 0 ? 0 : ((value % total) + total) % total;

  /// The production reader for the two-ahead opt-in; tests inject their own.
  static bool _readPrefetchSetting() => WallpaperPrefetchSetting.enabled;

  static String? _byline(AvesEntry entry) {
    final directory = entry.directory;
    if (directory == null || directory.isEmpty) return null;
    final name = p.basename(directory);
    return name.isEmpty ? null : name;
  }

  static Future<Size> _defaultTargetSize() async {
    final bridgeSize = await WallpaperBridge.instance.wallpaperSize();
    if (bridgeSize != null) return bridgeSize;
    try {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null && !view.physicalSize.isEmpty) return view.physicalSize;
    } catch (_) {
      // A headless isolate has no binding; the fallback below keeps the bake
      // possible until the background entrypoint injects the device size.
    }
    return const Size(1080, 2400);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
