import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_nav.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the grouped wallpaper's derived bottom-bar entry lands.
///
/// The entry is never written into the user's list, so the placement is decided
/// here: next to the visible-range entry, in one of the two separate modes, and
/// only when the user has not pinned the page themselves.
void main() {
  const all = AvesNavItem(route: CollectionPage.routeName);
  const albums = AvesNavItem(route: AlbumListPage.routeName);
  const range = AvesNavItem(route: VisibleRangePage.routeName);
  const wallpaper = AvesNavItem(route: GroupedWallpaperPage.routeName);

  List<String?> routes(List<AvesNavItem> items) => [for (final item in items) item.route];

  test('the default mode puts the wallpaper right of the visible range while the page is open', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: defaultGroupedWallpaperNavMode, pageVisible: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName, GroupedWallpaperPage.routeName],
    );
  });

  test('separateLeft puts it left of the visible range while the page is open', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateLeft, pageVisible: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, GroupedWallpaperPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('the entry follows the range entry wherever the user moved it', () {
    expect(
      routes(withWallpaperNavDestinations([all, range, albums], mode: GroupedWallpaperNavMode.separateRight, pageVisible: true)),
      [CollectionPage.routeName, VisibleRangePage.routeName, GroupedWallpaperPage.routeName, AlbumListPage.routeName],
    );
  });

  test('the shared mode keeps the single shell entry even while the page is open', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.shared, pageVisible: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('the bar grows by one while the wallpaper page is open and shrinks back after', () {
    // A user list of three entries plus the derived range entry: four normally.
    const configured = [all, albums, AvesNavItem(route: CollectionPage.routeName)];
    final closed = withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, pageVisible: false);
    expect(routes(closed), hasLength(4));
    expect(routes(closed), isNot(contains(GroupedWallpaperPage.routeName)));

    final open = withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, pageVisible: true);
    expect(routes(open), hasLength(5));
    // Right of the range entry, i.e. last here.
    expect(routes(open).last, GroupedWallpaperPage.routeName);

    // Leaving the page takes the entry away again.
    final after = withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, pageVisible: false);
    expect(routes(after), routes(closed));
  });

  test('an entry the user pinned is not duplicated', () {
    expect(
      routes(withWallpaperNavDestinations([all, wallpaper, albums], mode: GroupedWallpaperNavMode.separateRight, pageVisible: true)),
      [CollectionPage.routeName, GroupedWallpaperPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('picking a photo derives nothing', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, pageVisible: true, include: false)),
      [CollectionPage.routeName, AlbumListPage.routeName],
    );
  });

  test('an unknown stored mode falls back to the default', () {
    expect(groupedWallpaperNavModeFrom('nope'), defaultGroupedWallpaperNavMode);
    expect(groupedWallpaperNavModeFrom(null), defaultGroupedWallpaperNavMode);
    expect(groupedWallpaperNavModeFrom('shared'), GroupedWallpaperNavMode.shared);
  });

  test('closing flips the shared entry and navigates away otherwise', () {
    // One entry hosts both pages, so closing flips it in place and the bar keeps
    // a highlighted destination.
    expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.shared), WallpaperPageCloseTarget.rangeInPlace);
    // The page is its own route: closing goes back to the range page and its
    // temporary entry disappears with the page.
    expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.separateLeft), WallpaperPageCloseTarget.rangePage);
    expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.separateRight), WallpaperPageCloseTarget.rangePage);
  });

  test('the page marker is depth-based, so a replaced page never hides the entry', () {
    final controller = GroupedWallpaperNavController();
    expect(controller.pageVisible, isFalse);
    controller.enterPage();
    expect(controller.pageVisible, isTrue);
    // A replacement page starts before the old one disposes.
    controller.enterPage();
    controller.exitPage();
    expect(controller.pageVisible, isTrue);
    controller.exitPage();
    expect(controller.pageVisible, isFalse);
    // A stray exit never underflows.
    controller.exitPage();
    expect(controller.pageVisible, isFalse);
  });

  group('derived destinations', () {
    test('the bar only adds the visible-range entry', () {
      // The wallpaper entry is temporary and only appears while its page is
      // open, so the editor never lists it as a derived destination.
      expect(routes(derivedNavDestinations([all, albums])), [VisibleRangePage.routeName]);
    });

    test('shows nothing that is already the user\'s own', () {
      expect(derivedNavDestinations([all, range, wallpaper]), isEmpty);
    });

    test('a pinned wallpaper entry is not derived again', () {
      expect(routes(derivedNavDestinations([all, albums, wallpaper])), [VisibleRangePage.routeName]);
    });
  });
}
