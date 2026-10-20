import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_keys.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  });

  group('CollectionEngine', () {
    test('defaults to auto', () {
      expect(CollectionEngine.defaultEngine, CollectionEngine.auto);
    });

    test('tryParse round-trips member names', () {
      for (final engine in CollectionEngine.values) {
        expect(CollectionEngine.tryParse(engine.name), engine);
      }
    });

    test('tryParse rejects unknown and null', () {
      expect(CollectionEngine.tryParse('v3'), isNull);
      expect(CollectionEngine.tryParse(null), isNull);
    });
  });

  group('CollectionPagingPrefs', () {
    Future<void> clearKeys() async {
      final store = await SharedPreferences.getInstance();
      await store.remove(CollectionPagingKeys.engine);
      await store.remove(CollectionPagingKeys.windowSize);
      await store.remove(CollectionPagingKeys.prefetchScreens);
      await store.remove(CollectionPagingKeys.largeThreshold);
      await store.remove(CollectionPagingKeys.askBeforeCatalog);
      await store.remove(CollectionPagingKeys.importExplained);
      await store.remove(CollectionPagingKeys.importComplete);
    }

    test('starts on defaults when nothing is persisted', () async {
      await clearKeys();
      final prefs = CollectionPagingPrefs();
      await prefs.init();
      expect(prefs.engine, CollectionEngine.auto);
      expect(prefs.windowSize, CollectionPagingPrefs.defaultWindowSize);
      expect(prefs.prefetchScreens, CollectionPagingPrefs.defaultPrefetchScreens);
      expect(prefs.largeThreshold, CollectionPagingPrefs.defaultLargeThreshold);
      // Cataloguing is the steady state of a paged collection, so the backlog
      // question starts off; the one-time explainer says it once instead.
      expect(prefs.askBeforeCatalog, isFalse);
      expect(prefs.importExplained, isFalse);
      expect(prefs.importComplete, isFalse);
      // The default is the smallest preset: a library that big is served window
      // by window, so a low threshold costs nothing and keeps it off the full
      // load.
      expect(CollectionPagingPrefs.defaultLargeThreshold, CollectionPagingPrefs.largeThresholdPresets.first);
      expect(prefs.isLoaded, isTrue);
      prefs.dispose();
    });

    test('clamps window size into 1..max', () {
      expect(CollectionPagingPrefs.clampWindowSize(0), 1);
      expect(CollectionPagingPrefs.clampWindowSize(-40), 1);
      expect(CollectionPagingPrefs.clampWindowSize(200), 200);
      expect(CollectionPagingPrefs.clampWindowSize(100000), CollectionPagingPrefs.maxWindowSize);
    });

    test('clamps the large threshold into 1..max', () {
      expect(CollectionPagingPrefs.clampLargeThreshold(0), 1);
      expect(CollectionPagingPrefs.clampLargeThreshold(50000), 50000);
      expect(CollectionPagingPrefs.clampLargeThreshold(100000000), CollectionPagingPrefs.maxLargeThreshold);
    });

    test('persists and reloads values', () async {
      await clearKeys();
      final prefs = CollectionPagingPrefs();
      await prefs.init();
      await prefs.setEngine(CollectionEngine.legacy);
      await prefs.setWindowSize(400);
      await prefs.setPrefetchScreens(0);
      await prefs.setLargeThreshold(50000);
      prefs.dispose();

      final reloaded = CollectionPagingPrefs();
      await reloaded.init();
      expect(reloaded.engine, CollectionEngine.legacy);
      expect(reloaded.windowSize, 400);
      expect(reloaded.prefetchScreens, 0);
      expect(reloaded.largeThreshold, 50000);
      reloaded.dispose();
    });

    test('falls back to defaults on garbage', () async {
      final store = await SharedPreferences.getInstance();
      await store.setString(CollectionPagingKeys.engine, 'nope');
      await store.setInt(CollectionPagingKeys.windowSize, -12);
      await store.setInt(CollectionPagingKeys.prefetchScreens, 99);
      await store.setInt(CollectionPagingKeys.largeThreshold, -7);

      final prefs = CollectionPagingPrefs();
      await prefs.init();
      expect(prefs.engine, CollectionEngine.auto);
      expect(prefs.windowSize, 1);
      expect(prefs.prefetchScreens, CollectionPagingPrefs.maxPrefetchScreens);
      expect(prefs.largeThreshold, 1);
      prefs.dispose();
    });

    test('notifies listeners only on actual change', () async {
      await clearKeys();
      final prefs = CollectionPagingPrefs();
      await prefs.init();
      var notified = 0;
      prefs.addListener(() => notified++);
      await prefs.setEngine(CollectionEngine.legacy);
      expect(notified, 1);
      await prefs.setEngine(CollectionEngine.legacy);
      expect(notified, 1);
      prefs.dispose();
    });
  });
}
