import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/nav_drawer/model/drawer_page_routes.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/settings/defaults.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which page entries the drawer shows and which ones the editor offers.
///
/// The drawer is driven by one ordered list, so the fork's pages are ordinary
/// options there instead of fixed tiles; the defaults decide which of them a
/// fresh install sees.
void main() {
  group('defaults', () {
    test('a fresh install shows the visible range but neither wallpaper page', () {
      const pages = SettingsDefaults.drawerPageBookmarks;
      expect(pages, contains(VisibleRangePage.routeName));
      expect(pages, isNot(contains(MuzeiWallpaperPage.routeName)));
      expect(pages, isNot(contains(GroupedWallpaperPage.routeName)));
    });

    test('the visible range keeps the slot the fixed tile had', () {
      const pages = SettingsDefaults.drawerPageBookmarks;
      expect(pages.indexOf(VisibleRangePage.routeName), pages.indexOf(ExplorerPage.routeName) - 1);
    });
  });

  group('options', () {
    test('the editor offers the fork pages after the upstream ones', () {
      const upstream = [AlbumListPage.routeName, ExplorerPage.routeName];
      final options = drawerPageOptions(upstream);
      expect(options.take(upstream.length), upstream);
      expect(options.skip(upstream.length), forkDrawerPageRoutes);
    });

    test('a fork page already offered upstream is not offered twice', () {
      final options = drawerPageOptions(const [VisibleRangePage.routeName, AlbumListPage.routeName]);
      expect(options.where((route) => route == VisibleRangePage.routeName), hasLength(1));
    });
  });

  group('entries', () {
    test('a pick drops the fork pages and keeps every other page in place', () {
      const pages = [
        AlbumListPage.routeName,
        VisibleRangePage.routeName,
        GroupedWallpaperPage.routeName,
        ExplorerPage.routeName,
      ];
      expect(drawerPageEntries(pages, picking: true), [AlbumListPage.routeName, ExplorerPage.routeName]);
    });

    test('outside a pick the order is the user\'s own', () {
      const pages = [ExplorerPage.routeName, MuzeiWallpaperPage.routeName, AlbumListPage.routeName];
      expect(drawerPageEntries(pages, picking: false), pages);
    });
  });
}
