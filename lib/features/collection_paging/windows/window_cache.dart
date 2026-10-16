import 'dart:async';
import 'dart:collection';

import 'package:aves/features/logging/log.dart';

const _logChannel = 'log.collection_paging.cache';

const _log = AreaKeyLog(_logChannel);

/// Window-aligned LRU store over an async row source.
///
/// Windows are numbered `globalIndex ~/ windowSize`. Reads never block:
/// [peek] returns the cached window or null, and [ensure] schedules a fetch
/// for the missed window plus its neighbours (bounded by [prefetchWindows]).
/// Rapid misses coalesce: a fling settles into one fetch batch around its
/// destination instead of one query per crossed window. Completions from an
/// older [invalidate] generation are dropped, so a stale fetch can never
/// splice rows from a previous scope into the current view.
///
/// Eviction is plain LRU capped at [maxWindows]. Fills and evictions are
/// reported through [onFilled]/[onEvicted] so owners can mirror exactly what
/// the cache holds and stay bounded too.
class WindowCache<T> {
  final Future<List<T>> Function(int windowIndex, int limit, int offset) fetch;

  final int windowSize;

  final int prefetchWindows;

  final int maxWindows;

  final void Function(int windowIndex, List<T> rows)? onFilled;

  final void Function(int windowIndex)? onEvicted;

  new({
    required this.fetch,
    required this.windowSize,
    this.prefetchWindows = 2,
    this.maxWindows = 8,
    this.onFilled,
    this.onEvicted,
  });

  final LinkedHashMap<int, List<T>> _windows = LinkedHashMap();
  final Set<int> _inflight = {};
  int _generation = 0;
  int _latestRequestedIndex = 0;
  bool _drainScheduled = false;

  /// Cached rows for [windowIndex], or null. Touches LRU order, never fetches.
  List<T>? peek(int windowIndex) {
    final rows = _windows[windowIndex];
    if (rows == null) return null;
    _windows.remove(windowIndex);
    _windows[windowIndex] = rows;
    return rows;
  }

  /// Number of cached windows (test seam).
  int get cachedWindowCount => _windows.length;

  /// Whether [windowIndex] is cached or in flight (test seam).
  bool isPending(int windowIndex) => _windows.containsKey(windowIndex) || _inflight.contains(windowIndex);

  /// Fetches the window around [globalIndex] plus neighbours, unless cached.
  /// Fire-and-forget from synchronous reads; completions report via callbacks.
  void ensure(int globalIndex) {
    if (globalIndex < 0) return;
    final windowIndex = globalIndex ~/ windowSize;
    if (_windows.containsKey(windowIndex) || _inflight.contains(windowIndex)) return;
    _latestRequestedIndex = globalIndex;
    _scheduleDrain();
  }

  /// Awaits the window around [globalIndex] plus neighbours.
  Future<void> ensureAround(int globalIndex) async {
    ensure(globalIndex < 0 ? 0 : globalIndex);
    while (_drainScheduled || _inflight.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Drops everything; in-flight fills complete into the void.
  void invalidate() {
    _generation++;
    _windows.clear();
    _inflight.clear();
  }

  void _scheduleDrain() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    final center = _latestRequestedIndex ~/ windowSize;
    final targets = {
      for (var w = center - prefetchWindows; w <= center + prefetchWindows; w++) if (w >= 0) w,
    };
    for (final windowIndex in targets) {
      if (_windows.containsKey(windowIndex) || _inflight.contains(windowIndex)) continue;
      _inflight.add(windowIndex);
      final generation = _generation;
      try {
        final rows = await fetch(windowIndex, windowSize, windowIndex * windowSize);
        if (generation != _generation) return;
        _inflight.remove(windowIndex);
        _put(windowIndex, rows);
        onFilled?.call(windowIndex, rows);
      } catch (error, stack) {
        if (generation != _generation) return;
        _inflight.remove(windowIndex);
        _log.w('window $windowIndex fetch failed', error, stack);
      }
    }
  }

  void _put(int windowIndex, List<T> rows) {
    _windows.remove(windowIndex);
    _windows[windowIndex] = rows;
    while (_windows.length > maxWindows) {
      final evicted = _windows.keys.first;
      _windows.remove(evicted);
      onEvicted?.call(evicted);
    }
  }
}
