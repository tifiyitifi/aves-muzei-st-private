import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/session_restore/session_restore_plan.dart';
import 'package:aves/features/session_restore/session_restore_snapshot.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves/widgets/map/map_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  SessionRestoreSnapshot snapshot({
    required String route,
    String? baseRoute,
    Set<CollectionFilter> filters = const {},
    Set<CollectionFilter> baseFilters = const {},
  }) {
    return SessionRestoreSnapshot(
      routeName: route,
      filtersJson: [for (final filter in filters) filter.toJsonString()],
      baseRouteName: baseRoute,
      baseFiltersJson: [for (final filter in baseFilters) filter.toJsonString()],
    );
  }

  group('SessionRestorePlan', () {
    test('restores an ordinary page alone, with filters only for the collection', () {
      final collection = planSessionRestore(
        snapshot(route: CollectionPage.routeName, filters: {FavouriteFilter.instance}),
        homeRouteName: AlbumListPage.routeName,
      );

      expect(collection.routeName, CollectionPage.routeName);
      expect(collection.filters, {FavouriteFilter.instance});
      expect(collection.baseRouteName, isNull);
      expect(collection.baseFilters, isNull);

      final map = planSessionRestore(snapshot(route: MapPage.routeName), homeRouteName: CollectionPage.routeName);

      expect(map.routeName, MapPage.routeName);
      expect(map.filters, isNull);
      expect(map.baseRouteName, isNull);
    });

    test('keeps an empty collection set distinct from the home collection', () {
      final plan = planSessionRestore(snapshot(route: CollectionPage.routeName), homeRouteName: CollectionPage.routeName);

      // An empty set means "all media", so it must override the home filters.
      expect(plan.filters, isNotNull);
      expect(plan.filters, isEmpty);
    });

    test('restores a pushed page over the page it was opened from', () {
      final plan = planSessionRestore(
        snapshot(
          route: MuzeiWallpaperPage.routeName,
          baseRoute: CollectionPage.routeName,
          baseFilters: {FavouriteFilter.instance},
        ),
        homeRouteName: AlbumListPage.routeName,
      );

      expect(plan.routeName, MuzeiWallpaperPage.routeName);
      expect(plan.filters, isNull);
      expect(plan.baseRouteName, CollectionPage.routeName);
      expect(plan.baseFilters, {FavouriteFilter.instance});
    });

    test('does not invent filters for a base that is not the collection', () {
      final plan = planSessionRestore(
        snapshot(
          route: MuzeiWallpaperPage.routeName,
          baseRoute: AlbumListPage.routeName,
          baseFilters: {FavouriteFilter.instance},
        ),
        homeRouteName: CollectionPage.routeName,
      );

      expect(plan.baseRouteName, AlbumListPage.routeName);
      expect(plan.baseFilters, isNull);
    });

    test('stands the configured home page in for a snapshot saved without a base', () {
      final plan = planSessionRestore(
        snapshot(route: MuzeiWallpaperPage.routeName),
        homeRouteName: TagListPage.routeName,
      );

      expect(plan.baseRouteName, TagListPage.routeName);
      // The stand-in keeps its own configured filters, not the snapshot's.
      expect(plan.baseFilters, isNull);
    });

    test('stands a collection in when the home page is the pushed page itself', () {
      final plan = planSessionRestore(
        snapshot(route: MuzeiWallpaperPage.routeName),
        homeRouteName: MuzeiWallpaperPage.routeName,
      );

      expect(plan.baseRouteName, CollectionPage.routeName);
      expect(plan.baseFilters, isNull);
    });

    test('ignores a base saved under a page that is not pushed', () {
      final plan = planSessionRestore(
        snapshot(route: CollectionPage.routeName, baseRoute: MapPage.routeName),
        homeRouteName: AlbumListPage.routeName,
      );

      expect(plan.routeName, CollectionPage.routeName);
      expect(plan.baseRouteName, isNull);
    });

    test('restores the wallpaper page over the page it was opened from', () {
      final plan = planSessionRestore(
        snapshot(route: GroupedWallpaperPage.routeName, baseRoute: VisibleRangePage.routeName),
        homeRouteName: CollectionPage.routeName,
      );

      expect(plan.routeName, GroupedWallpaperPage.routeName);
      expect(plan.filters, isNull);
      expect(plan.baseRouteName, VisibleRangePage.routeName);
      expect(plan.baseFilters, isNull);
      // The wallpaper page is its own route, so the shared entry flag means
      // nothing here.
      expect(plan.rangeWallpaper, isFalse);
    });

    test('stands the home page in under the wallpaper page when no base was saved', () {
      final plan = planSessionRestore(
        snapshot(route: GroupedWallpaperPage.routeName),
        homeRouteName: AlbumListPage.routeName,
      );

      expect(plan.routeName, GroupedWallpaperPage.routeName);
      expect(plan.baseRouteName, AlbumListPage.routeName);
    });

    test('carries the shared entry sub-page for the range route only', () {
      const range = SessionRestoreSnapshot(routeName: VisibleRangePage.routeName, rangeWallpaper: true);
      final shared = planSessionRestore(range, homeRouteName: CollectionPage.routeName);

      expect(shared.routeName, VisibleRangePage.routeName);
      expect(shared.rangeWallpaper, isTrue);

      // The same flag under another route is stale and must not reopen a page the
      // user never had.
      const other = SessionRestoreSnapshot(routeName: MapPage.routeName, rangeWallpaper: true);
      expect(planSessionRestore(other, homeRouteName: CollectionPage.routeName).rangeWallpaper, isFalse);
    });
  });
}
