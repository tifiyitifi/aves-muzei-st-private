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
    test('defaults to paged', () {
      expect(CollectionEngine.defaultEngine, CollectionEngine.paged);
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
    }

    test('starts on defaults when nothing is persisted', () async {
      await clearKeys();
      final prefs = CollectionPagingPrefs();
      await prefs.init();
      expect(prefs.engine, CollectionEngine.paged);
      expect(prefs.windowSize, CollectionPagingPrefs.defaultWindowSize);
      expect(prefs.prefetchScreens, CollectionPagingPrefs.defaultPrefetchScreens);
      expect(prefs.isLoaded, isTrue);
      prefs.dispose();
    });

    test('clamps window size into 1..max', () {
      expect(CollectionPagingPrefs.clampWindowSize(0), 1);
      expect(CollectionPagingPrefs.clampWindowSize(-40), 1);
      expect(CollectionPagingPrefs.clampWindowSize(200), 200);
      expect(CollectionPagingPrefs.clampWindowSize(100000), CollectionPagingPrefs.maxWindowSize);
    });

    test('persists and reloads values', () async {
      await clearKeys();
      final prefs = CollectionPagingPrefs();
      await prefs.init();
      await prefs.setEngine(CollectionEngine.legacy);
      await prefs.setWindowSize(400);
      await prefs.setPrefetchScreens(0);
      prefs.dispose();

      final reloaded = CollectionPagingPrefs();
      await reloaded.init();
      expect(reloaded.engine, CollectionEngine.legacy);
      expect(reloaded.windowSize, 400);
      expect(reloaded.prefetchScreens, 0);
      reloaded.dispose();
    });

    test('falls back to defaults on garbage', () async {
      final store = await SharedPreferences.getInstance();
      await store.setString(CollectionPagingKeys.engine, 'nope');
      await store.setInt(CollectionPagingKeys.windowSize, -12);
      await store.setInt(CollectionPagingKeys.prefetchScreens, 99);

      final prefs = CollectionPagingPrefs();
      await prefs.init();
      expect(prefs.engine, CollectionEngine.paged);
      expect(prefs.windowSize, 1);
      expect(prefs.prefetchScreens, CollectionPagingPrefs.maxPrefetchScreens);
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
