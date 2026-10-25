import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/session_restore/session_restore_snapshot.dart';
import 'package:aves/features/session_restore/session_restore_store.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/map/map_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common.dart';

void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionRestoreSnapshot', () {
    test('round-trips the route and its filters', () {
      final snapshot = SessionRestoreSnapshot(
        routeName: CollectionPage.routeName,
        filtersJson: [
          MimeFilter.image.toJsonString(),
          FavouriteFilter.instance.toJsonString(),
        ],
      );

      final decoded = SessionRestoreSnapshot.tryFromJsonString(snapshot.toJsonString());
      expect(decoded, isNotNull);
      expect(decoded!.routeName, CollectionPage.routeName);
      expect(decoded.filters, {MimeFilter.image, FavouriteFilter.instance});
      expect(decoded.isValid, isTrue);
    });

    test('rejects a route the app cannot reopen', () {
      final snapshot = SessionRestoreSnapshot(
        routeName: '/not-restorable',
        filtersJson: [MimeFilter.image.toJsonString()],
      );

      expect(SessionRestoreSnapshot.tryFromJsonString(snapshot.toJsonString()), isNull);
    });

    test('tolerates malformed or empty input', () {
      expect(SessionRestoreSnapshot.tryFromJsonString(null), isNull);
      expect(SessionRestoreSnapshot.tryFromJsonString(''), isNull);
      expect(SessionRestoreSnapshot.tryFromJsonString('{'), isNull);
      expect(SessionRestoreSnapshot.tryFromJsonString('{"route": 42}'), isNull);
    });

    test('accepts a page without filters', () {
      const snapshot = SessionRestoreSnapshot(routeName: MapPage.routeName);
      final decoded = SessionRestoreSnapshot.tryFromJsonString(snapshot.toJsonString());
      expect(decoded?.routeName, MapPage.routeName);
      expect(decoded?.filters, isEmpty);
    });

    test('round-trips the page a pushed page was opened from', () {
      final snapshot = SessionRestoreSnapshot(
        routeName: MuzeiWallpaperPage.routeName,
        baseRouteName: CollectionPage.routeName,
        baseFiltersJson: [FavouriteFilter.instance.toJsonString()],
      );

      final decoded = SessionRestoreSnapshot.tryFromJsonString(snapshot.toJsonString());
      expect(decoded, isNotNull);
      expect(decoded!.routeName, MuzeiWallpaperPage.routeName);
      expect(decoded.baseRouteName, CollectionPage.routeName);
      expect(decoded.baseFilters, {FavouriteFilter.instance});
      expect(decoded.isValid, isTrue);
    });

    test('reads a snapshot saved before the base page existed', () {
      // This is what an upgraded install still has on disk.
      final decoded = SessionRestoreSnapshot.tryFromJsonString('{"route":"${MuzeiWallpaperPage.routeName}"}');

      expect(decoded, isNotNull);
      expect(decoded!.routeName, MuzeiWallpaperPage.routeName);
      expect(decoded.baseRouteName, isNull);
      expect(decoded.isValid, isTrue);
    });

    test('drops an unusable base but keeps the page', () {
      final decoded = SessionRestoreSnapshot.tryFromJsonString(
        '{"route":"${MuzeiWallpaperPage.routeName}","baseRoute":"/not-restorable","baseFilters":["bad"]}',
      );

      expect(decoded, isNotNull);
      expect(decoded!.routeName, MuzeiWallpaperPage.routeName);
      expect(decoded.baseRouteName, isNull);
      expect(decoded.baseFilters, isEmpty);
      expect(decoded.isValid, isTrue);
    });

    test('drops a base pointing at the page itself', () {
      final decoded = SessionRestoreSnapshot.tryFromJsonString(
        '{"route":"${MuzeiWallpaperPage.routeName}","baseRoute":"${MuzeiWallpaperPage.routeName}"}',
      );

      expect(decoded?.baseRouteName, isNull);
      expect(decoded?.isValid, isTrue);
    });

    test('drops a base saved under a page that is not pushed', () {
      final decoded = SessionRestoreSnapshot.tryFromJsonString(
        '{"route":"${CollectionPage.routeName}","baseRoute":"${MapPage.routeName}"}',
      );

      expect(decoded, isNotNull);
      expect(decoded!.routeName, CollectionPage.routeName);
      expect(decoded.baseRouteName, isNull);
      expect(decoded.isValid, isTrue);
    });

    test('considers a base saved under a page that is not pushed invalid', () {
      const snapshot = SessionRestoreSnapshot(routeName: CollectionPage.routeName, baseRouteName: MapPage.routeName);

      expect(snapshot.isValid, isFalse);
    });
  });

  group('SessionRestoreStore', () {
    late SessionRestoreStore store;

    setUp(() {
      store = SessionRestoreStore();
    });

    test('saves, loads and clears the snapshot', () async {
      final snapshot = SessionRestoreSnapshot(
        routeName: CollectionPage.routeName,
        filtersJson: [FavouriteFilter.instance.toJsonString()],
      );

      await store.save(snapshot);
      final loaded = await store.load();
      expect(loaded?.routeName, CollectionPage.routeName);
      expect(loaded?.filters, {FavouriteFilter.instance});

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('does not persist an invalid route', () async {
      await store.save(const SessionRestoreSnapshot(routeName: '/not-restorable'));
      expect(await store.load(), isNull);
    });

    test('does not persist a base saved under a page that is not pushed', () async {
      await store.save(const SessionRestoreSnapshot(routeName: CollectionPage.routeName, baseRouteName: MapPage.routeName));
      expect(await store.load(), isNull);
    });
  });
}
