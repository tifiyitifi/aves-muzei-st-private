import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/session_restore/session_restore_route_observer.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Route<void> _route(String name) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name),
  pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
);

void main() {
  late SessionRestoreRouteObserver observer;

  setUp(() => observer = SessionRestoreRouteObserver());

  Route<void> push(String name) {
    final route = _route(name);
    observer.didPush(route, null);
    return route;
  }

  test('an ordinary page has no base page', () {
    push(CollectionPage.routeName);

    expect(observer.currentRestorableRoute, CollectionPage.routeName);
    expect(observer.currentRestorableBaseRoute, isNull);
  });

  test('a pushed page reports the page it was opened from', () {
    push(CollectionPage.routeName);
    push(MuzeiWallpaperPage.routeName);

    expect(observer.currentRestorableRoute, MuzeiWallpaperPage.routeName);
    expect(observer.currentRestorableBaseRoute, CollectionPage.routeName);
  });

  test('the base is the nearest restorable page below', () {
    push(AlbumListPage.routeName);
    push(MuzeiWallpaperPage.routeName);

    expect(observer.currentRestorableBaseRoute, AlbumListPage.routeName);
  });

  test('a non-restorable page above the pushed page does not move the base', () {
    push(CollectionPage.routeName);
    push(MuzeiWallpaperPage.routeName);
    // The wallpaper sub-pages (sources, gestures) have their own route names
    // that are not restorable.
    push('/muzei_wallpaper/sources');

    expect(observer.currentRestorableRoute, MuzeiWallpaperPage.routeName);
    expect(observer.currentRestorableBaseRoute, CollectionPage.routeName);
  });

  test('a non-restorable page below leaves no base', () {
    push(ExplorerPage.routeName);
    push(MuzeiWallpaperPage.routeName);

    expect(observer.currentRestorableRoute, MuzeiWallpaperPage.routeName);
    expect(observer.currentRestorableBaseRoute, isNull);
  });

  test('popping the pushed page restores the ordinary behavior', () {
    push(CollectionPage.routeName);
    final muzei = push(MuzeiWallpaperPage.routeName);
    observer.didPop(muzei, null);

    expect(observer.currentRestorableRoute, CollectionPage.routeName);
    expect(observer.currentRestorableBaseRoute, isNull);
  });

  test('the wallpaper page is restored over the page it was opened from', () {
    push(CollectionPage.routeName);
    push(VisibleRangePage.routeName);
    push(GroupedWallpaperPage.routeName);

    // Without the wallpaper page in the restorable set, the snapshot would only
    // remember the range page underneath and reopen that instead.
    expect(observer.currentRestorableRoute, GroupedWallpaperPage.routeName);
    expect(observer.currentRestorableBaseRoute, VisibleRangePage.routeName);
  });

  test('a page above the wallpaper page does not move the base', () {
    push(CollectionPage.routeName);
    push(GroupedWallpaperPage.routeName);
    // The wallpaper view and the usage history are transient sub-pages.
    push(GroupedWallpaperViewPage.routeName);

    expect(observer.currentRestorableRoute, GroupedWallpaperPage.routeName);
    expect(observer.currentRestorableBaseRoute, CollectionPage.routeName);
  });
}
