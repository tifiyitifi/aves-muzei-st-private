import 'dart:io';
import 'dart:math' as math;

import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WallpaperStateStore.runExclusive`: the page and the background refill are
/// separate isolates writing the same directory.
void main() {
  late Directory tempDir;
  late WallpaperStateStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aves_muzei_store_');
    store = WallpaperStateStore(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; the assertion result is more useful.
    }
  });

  test('a nested exclusive section reuses the held lock', () async {
    var innerRan = false;
    await store.runExclusive(() async {
      await store.runExclusive(() async {
        innerRan = true;
      });
    });
    expect(innerRan, isTrue);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('two stores on the same directory never write at the same time', () async {
    final other = WallpaperStateStore(tempDir);
    var active = 0;
    var peak = 0;

    Future<void> work(WallpaperStateStore target) => target.runExclusive(() async {
      active++;
      peak = math.max(peak, active);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      active--;
    });

    await Future.wait([work(store), work(other)]);

    expect(peak, 1);
  });
}
