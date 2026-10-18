import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// A catalog pass's progress over time.
class CatalogProgress {
  final int done;

  /// The pass's row count, or 0 when it is unknown (the locate passes).
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

/// Live progress of the background catalog/locate passes, for the app bar.
///
/// The passes report rows through `source.setProgress`; the worker feeds this
/// notifier too, which adds the two things a bare counter cannot say: how long
/// the pass has been running, and how long it is likely to take.
///
/// The estimate is a rolling rate over recent samples, so a stall or a burst
/// moves the ETA instead of being averaged away. It is withheld until the pass
/// has both run for a while and moved a few rows: a wild guess in the first
/// second is worse than no number.
class CatalogProgressNotifier extends ValueNotifier<CatalogProgress?> {
  /// An estimate needs this much history before it is shown.
  static const estimateMinElapsed = Duration(seconds: 30);
  static const estimateMinRows = 50;

  /// How much history the rolling rate is measured over.
  static const rateWindow = Duration(seconds: 30);

  DateTime? _startedAt;
  final List<({DateTime at, int done})> _samples = [];

  new() : super(null);

  /// Reports a pass's progress. `total` of 0 means "unknown", and a `done` of 0
  /// starts a new pass.
  void update({required int done, required int total, required DateTime now}) {
    if (done == 0) {
      _samples.clear();
      _startedAt = now;
    }
    final startedAt = _startedAt ??= now;
    _samples.add((at: now, done: done));
    final cutoff = now.subtract(rateWindow);
    _samples.removeWhere((sample) => sample.at.isBefore(cutoff));
    value = CatalogProgress(
      done: done,
      total: total,
      elapsed: now.difference(startedAt),
      remaining: _estimate(done: done, total: total, now: now, startedAt: startedAt),
    );
  }

  /// Clears the pass, e.g. when it finishes and the source goes ready.
  void finish() {
    _startedAt = null;
    _samples.clear();
    value = null;
  }

  Duration? _estimate({required int done, required int total, required DateTime now, required DateTime startedAt}) {
    if (total <= 0 || done <= 0) return null;
    if (now.difference(startedAt) < estimateMinElapsed || done < estimateMinRows) return null;
    final first = _samples.firstOrNull;
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
