import 'package:aves/features/collection_paging/catalog/catalog_progress.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalog progress notifier's clock and estimate: a rolling rate that
/// withholds a guess until it is worth showing.
void main() {
  final start = DateTime(2024, 1, 1);

  CatalogProgress? report(CatalogProgressNotifier notifier, {required int done, required int total, required Duration after}) {
    notifier.update(done: done, total: total, now: start.add(after));
    return notifier.value;
  }

  group('CatalogProgressNotifier', () {
    test('withholds the estimate until the pass has history', () {
      // A pass that just started: elapsed only.
      final fresh = CatalogProgressNotifier();
      expect(report(fresh, done: 0, total: 1000, after: Duration.zero)!.remaining, isNull);

      // Too few rows moved to know a rate, however long it ran.
      final slow = CatalogProgressNotifier();
      report(slow, done: 0, total: 1000, after: Duration.zero);
      expect(report(slow, done: 5, total: 1000, after: const Duration(seconds: 10))!.remaining, isNull);

      // Rows moved, but the clock has not run long enough to trust it.
      final quick = CatalogProgressNotifier();
      report(quick, done: 0, total: 1000, after: Duration.zero);
      expect(report(quick, done: 100, total: 1000, after: const Duration(seconds: 1))!.remaining, isNull);
    });

    test('estimates as soon as a few rows have moved', () {
      // The pass now ticks every 10 rows, so the estimate must not wait for the
      // half-minute the first implementation required: that window is exactly
      // where the counter used to look stuck.
      final notifier = CatalogProgressNotifier();
      report(notifier, done: 0, total: 1000, after: Duration.zero);
      report(notifier, done: 10, total: 1000, after: const Duration(seconds: 2));
      final progress = report(notifier, done: 20, total: 1000, after: const Duration(seconds: 5))!;

      expect(progress.elapsed, const Duration(seconds: 5));
      expect(progress.remaining, isNotNull);
    });

    test('estimates the remaining time from the rolling rate', () {
      final notifier = CatalogProgressNotifier();
      report(notifier, done: 0, total: 1000, after: Duration.zero);
      report(notifier, done: 100, total: 1000, after: const Duration(seconds: 30));
      final progress = report(notifier, done: 300, total: 1000, after: const Duration(seconds: 60))!;

      // The window covers the last 30s, which did 200 rows: the 700 left take
      // about 105s, not the 140s the whole pass has averaged.
      expect(progress.elapsed, const Duration(seconds: 60));
      expect(progress.remaining!.inSeconds, closeTo(105, 5));
    });

    test('a burst moves the estimate instead of being averaged away', () {
      final notifier = CatalogProgressNotifier();
      report(notifier, done: 0, total: 1000, after: Duration.zero);
      report(notifier, done: 50, total: 1000, after: const Duration(seconds: 40));
      report(notifier, done: 500, total: 1000, after: const Duration(seconds: 50));

      // The last 10s did 450 rows, so the 500 left take about 11s.
      expect(notifier.value!.remaining!.inSeconds, closeTo(11, 3));
    });

    test('clears on finish and restarts on a new pass', () {
      final notifier = CatalogProgressNotifier();
      report(notifier, done: 0, total: 100, after: Duration.zero);
      report(notifier, done: 50, total: 100, after: const Duration(seconds: 40));
      notifier.finish();
      expect(notifier.value, isNull);

      // A new pass restarts the clock: no elapsed carried over.
      final progress = report(notifier, done: 0, total: 100, after: const Duration(seconds: 60))!;
      expect(progress.elapsed, Duration.zero);
    });

    test('an unknown total still reports the clock, without an estimate', () {
      final notifier = CatalogProgressNotifier();
      final progress = report(notifier, done: 0, total: 0, after: Duration.zero)!;
      report(notifier, done: 200, total: 0, after: const Duration(seconds: 90));

      expect(progress.total, 0);
      expect(notifier.value!.elapsed, const Duration(seconds: 90));
      expect(notifier.value!.remaining, isNull);
    });

    test('a later pass does not rewind the session', () {
      // The worker sweeps the current view first, then the rest of the library:
      // each pass has its own small counter, but the user watches one session.
      final notifier = CatalogProgressNotifier()..begin(total: 1000, now: start);
      report(notifier, done: 300, total: 1000, after: const Duration(seconds: 20));
      final progress = report(notifier, done: 0, total: 700, after: const Duration(seconds: 21))!;

      expect(progress.done, 300);
      expect(progress.total, 1000);
      expect(progress.elapsed, const Duration(seconds: 21));
    });

    test('the session total only grows, and the count never passes it', () {
      final notifier = CatalogProgressNotifier()..begin(total: 100, now: start);
      expect(report(notifier, done: 80, total: 0, after: const Duration(seconds: 5))!.total, 100);
      // New rows appeared: the work grew, so the denominator grows with it.
      expect(report(notifier, done: 120, total: 150, after: const Duration(seconds: 10))!.total, 150);
      // Rows catalogued by the analysis service: the count is clamped, not shown
      // as "160 of 150".
      final progress = report(notifier, done: 160, total: 0, after: const Duration(seconds: 15))!;
      expect(progress.done, 150);
      expect(progress.total, 150);
    });
  });

  group('formatCatalogDuration', () {
    test('minutes and seconds below an hour, hours above it', () {
      expect(formatCatalogDuration(Duration.zero), '0:00');
      expect(formatCatalogDuration(const Duration(seconds: 42)), '0:42');
      expect(formatCatalogDuration(const Duration(minutes: 2, seconds: 18)), '2:18');
      expect(formatCatalogDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(formatCatalogDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(formatCatalogDuration(const Duration(hours: 10)), '10:00:00');
    });
  });
}
