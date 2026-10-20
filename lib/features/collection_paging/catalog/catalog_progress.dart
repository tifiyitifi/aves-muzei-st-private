import 'package:flutter/foundation.dart';

/// A catalog session's progress over time.
class CatalogProgress {
  final int done;

  /// The session's row count, i.e. the backlog it started with, or 0 when it is
  /// unknown.
  final int total;

  final Duration elapsed;

  /// Estimated remaining time, or null while no estimate is trustworthy yet.
  final Duration? remaining;

  const new({
    required this.done,
    required this.total,
    required this.elapsed,
    this.remaining,
  });
}

/// Live progress of the background catalog passes, for the app bar.
///
/// A *session* is one drain of the worker, which may run several passes in a
/// row (the current view, the rest of the library, the offline countries). Only
/// the session is meaningful to the user: each pass restarts its own counters,
/// and reporting them directly made the number jump backwards and the
/// denominator change size between passes. Here the denominator is fixed when
/// the session starts and the numerator only ever moves forward, so "N of M"
/// reads like the old full load did.
///
/// The estimate is a rolling rate over recent samples, so a stall or a burst
/// moves the ETA instead of being averaged away. It is withheld until the pass
/// has both run for a while and moved a few rows: a wild guess in the first
/// second is worse than no number.
class CatalogProgressNotifier extends ValueNotifier<CatalogProgress?> {
  /// An estimate needs this much history before it is shown.
  ///
  /// Small on purpose: the pass now reports every few rows, and an estimate
  /// that only appears after half a minute leaves the user staring at a
  /// counter that looks stuck.
  static const estimateMinElapsed = Duration(seconds: 5);
  static const estimateMinRows = 10;

  /// How much history the rolling rate is measured over.
  static const rateWindow = Duration(seconds: 30);

  DateTime? _startedAt;
  int _done = 0;
  int _total = 0;
  final List<({DateTime at, int done})> _samples = [];

  new() : super(null);

  /// Starts a session. [total] is the backlog the session will work through and
  /// stays fixed for its whole duration; 0 means the size is unknown.
  void begin({required int total, required DateTime now}) {
    _startedAt = now;
    _done = 0;
    _total = total;
    _samples.clear();
    value = CatalogProgress(done: 0, total: total, elapsed: Duration.zero);
  }

  /// Reports the session's progress. Neither number moves backwards: a pass
  /// that starts over cannot rewind what the session already achieved.
  void update({required int done, required int total, required DateTime now}) {
    final startedAt = _startedAt ??= now;
    final nextTotal = total > _total ? total : _total;
    var nextDone = done > _done ? done : _done;
    if (nextTotal > 0 && nextDone > nextTotal) nextDone = nextTotal;
    _done = nextDone;
    _total = nextTotal;

    _samples.add((at: now, done: nextDone));
    final cutoff = now.subtract(rateWindow);
    _samples.removeWhere((sample) => sample.at.isBefore(cutoff));
    value = CatalogProgress(
      done: nextDone,
      total: nextTotal,
      elapsed: now.difference(startedAt),
      remaining: _estimate(done: nextDone, total: nextTotal, now: now, startedAt: startedAt),
    );
  }

  /// Clears the session, e.g. when the worker is done and the source goes ready.
  void finish() {
    _startedAt = null;
    _done = 0;
    _total = 0;
    _samples.clear();
    value = null;
  }

  Duration? _estimate({required int done, required int total, required DateTime now, required DateTime startedAt}) {
    if (total <= 0 || done <= 0) return null;
    if (now.difference(startedAt) < estimateMinElapsed || done < estimateMinRows) return null;
    final first = _samples.isEmpty ? null : _samples.first;
    if (first == null) return null;
    final spanMs = now.difference(first.at).inMilliseconds;
    if (spanMs <= 0) return null;
    final rowsPerMs = (done - first.done) / spanMs;
    if (rowsPerMs <= 0) return null;
    final remainingMs = (total - done) / rowsPerMs;
    return remainingMs <= 0 ? Duration.zero : Duration(milliseconds: remainingMs.round());
  }
}

/// `h:mm:ss` past an hour, `m:ss` below it, like a media player's clock.
String formatCatalogDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
}

/// The app's single progress notifier: the worker writes, the app bar reads.
final CatalogProgressNotifier catalogProgressNotifier = CatalogProgressNotifier();
