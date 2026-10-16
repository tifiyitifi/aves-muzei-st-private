import 'package:aves/features/collection_paging/windows/window_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Window alignment, coalescing, stale-fill drops and LRU eviction.
void main() {
  // Rows are `globalIndex * 10`, so any misplacement is visible.
  Future<List<int>> fetch(int windowIndex, int limit, int offset) async => [for (var i = 0; i < limit; i++) (offset + i) * 10];

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('WindowCache', () {
    test('a miss fetches the window plus neighbours', () async {
      var fills = 0;
      final cache = WindowCache<int>(
        fetch: fetch,
        windowSize: 4,
        prefetchWindows: 1,
        onFilled: (windowIndex, rows) => fills++,
      );
      expect(cache.peek(1), isNull);
      cache.ensure(5);
      await flush();
      expect(fills, 3);
      // window 1 (global 4..7) plus neighbours 0 and 2
      expect(cache.peek(1), [40, 50, 60, 70]);
      expect(cache.peek(0), [0, 10, 20, 30]);
      expect(cache.peek(2), [80, 90, 100, 110]);
    });

    test('rapid misses coalesce into one batch', () async {
      var fetches = 0;
      final cache = WindowCache<int>(
        fetch: (w, limit, offset) async {
          fetches++;
          return fetch(w, limit, offset);
        },
        windowSize: 4,
        prefetchWindows: 1,
      );
      cache.ensure(0);
      cache.ensure(40);
      cache.ensure(80);
      await flush();
      // only the destination neighbourhood (windows around 80) is fetched
      expect(fetches, 3);
      expect(cache.peek(20), [800, 810, 820, 830]);
      expect(cache.peek(0), isNull);
    });

    test('a fill from before invalidate is dropped', () async {
      var release = false;
      var fills = 0;
      final cache = WindowCache<int>(
        fetch: (w, limit, offset) async {
          while (!release) {
            await Future<void>.delayed(Duration.zero);
          }
          return fetch(w, limit, offset);
        },
        windowSize: 4,
        prefetchWindows: 0,
        onFilled: (windowIndex, rows) => fills++,
      );
      cache.ensure(0);
      await Future<void>.delayed(Duration.zero);
      cache.invalidate();
      release = true;
      await flush();
      expect(fills, 0);
      expect(cache.peek(0), isNull);
      expect(cache.cachedWindowCount, 0);
    });

    test('evictions report and stay bounded', () async {
      final evicted = <int>[];
      final cache = WindowCache<int>(
        fetch: fetch,
        windowSize: 4,
        prefetchWindows: 0,
        maxWindows: 2,
        onEvicted: evicted.add,
      );
      await cache.ensureAround(0);
      await cache.ensureAround(4);
      expect(cache.cachedWindowCount, 2);
      await cache.ensureAround(8);
      expect(cache.cachedWindowCount, 2);
      expect(evicted, [0]);
      expect(cache.peek(0), isNull);
      expect(cache.peek(2), [80, 90, 100, 110]);
    });

    test('negative indexes never fetch', () async {
      var fetches = 0;
      final cache = WindowCache<int>(
        fetch: (w, limit, offset) async {
          fetches++;
          return fetch(w, limit, offset);
        },
        windowSize: 4,
      );
      cache.ensure(-1);
      await flush();
      expect(fetches, 0);
    });
  });
}
