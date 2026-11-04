import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_nav.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the grouped wallpaper's derived bottom-bar entry lands and how closing
/// its page returns.
///
/// The entry is never written into the user's list, so the placement is decided
/// here: next to the visible-range entry, in one of the two separate modes, and
/// only while the page's session is open and the user has not pinned it.
void main() {
  const all = AvesNavItem(route: CollectionPage.routeName);
  const albums = AvesNavItem(route: AlbumListPage.routeName);
  const range = AvesNavItem(route: VisibleRangePage.routeName);
  const wallpaper = AvesNavItem(route: GroupedWallpaperPage.routeName);

  List<String?> routes(List<AvesNavItem> items) => [for (final item in items) item.route];

  test('the default mode puts the wallpaper right of the visible range while the session is open', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: defaultGroupedWallpaperNavMode, sessionActive: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName, GroupedWallpaperPage.routeName],
    );
  });

  test('separateLeft puts it left of the visible range while the session is open', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateLeft, sessionActive: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, GroupedWallpaperPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('the entry follows the range entry wherever the user moved it', () {
    expect(
      routes(withWallpaperNavDestinations([all, range, albums], mode: GroupedWallpaperNavMode.separateRight, sessionActive: true)),
      [CollectionPage.routeName, VisibleRangePage.routeName, GroupedWallpaperPage.routeName, AlbumListPage.routeName],
    );
  });

  test('the shared mode keeps the single shell entry even while the session is open', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.shared, sessionActive: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('the entry survives leaving the page and only a close takes it away', () {
    // A user list of three entries plus the derived range entry: four normally.
    const configured = [all, albums, AvesNavItem(route: CollectionPage.routeName)];
    final closed = withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, sessionActive: false);
    expect(routes(closed), hasLength(4));
    expect(routes(closed), isNot(contains(GroupedWallpaperPage.routeName)));

    final open = withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, sessionActive: true);
    expect(routes(open), hasLength(5));
    // Right of the range entry, i.e. last here.
    expect(routes(open).last, GroupedWallpaperPage.routeName);

    // Switching to the media set or the albums page disposes the page but keeps
    // the session, so the entry is still there to come back to.
    final after = withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, sessionActive: true);
    expect(routes(after), routes(open));

    // Closing the session takes it away again.
    expect(
      routes(withWallpaperNavDestinations(configured, mode: GroupedWallpaperNavMode.separateRight, sessionActive: false)),
      routes(closed),
    );
  });

  test('an entry the user pinned is not duplicated', () {
    expect(
      routes(withWallpaperNavDestinations([all, wallpaper, albums], mode: GroupedWallpaperNavMode.separateRight, sessionActive: true)),
      [CollectionPage.routeName, GroupedWallpaperPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('picking a photo derives nothing', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, sessionActive: true, include: false)),
      [CollectionPage.routeName, AlbumListPage.routeName],
    );
  });

  test('an unknown stored mode falls back to the default', () {
    expect(groupedWallpaperNavModeFrom('nope'), defaultGroupedWallpaperNavMode);
    expect(groupedWallpaperNavModeFrom(null), defaultGroupedWallpaperNavMode);
    expect(groupedWallpaperNavModeFrom('shared'), GroupedWallpaperNavMode.shared);
  });

  group('close target', () {
    test('the shared entry flips in place, whatever the stack holds', () {
      // One entry hosts both pages, so closing lands on the range page instead of
      // popping the shell the user is looking at.
      expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.shared, canPop: true), WallpaperPageCloseTarget.rangeInPlace);
      expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.shared, canPop: false), WallpaperPageCloseTarget.rangeInPlace);
    });

    test('a page the bar pushed pops back to the page underneath', () {
      expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.separateLeft, canPop: true), WallpaperPageCloseTarget.pop);
      expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.separateRight, canPop: true), WallpaperPageCloseTarget.pop);
    });

    test('a page that replaced the stack lands on the range page', () {
      expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.separateLeft, canPop: false), WallpaperPageCloseTarget.rangePage);
      expect(wallpaperPageCloseTarget(GroupedWallpaperNavMode.separateRight, canPop: false), WallpaperPageCloseTarget.rangePage);
    });
  });

  test('the session survives page visits and ends on a single close', () {
    final controller = GroupedWallpaperNavController();
    expect(controller.sessionActive, isFalse);
    controller.openSession();
    expect(controller.sessionActive, isTrue);
    // Leaving the page never closes the session, so a second visit must not need
    // a second close.
    controller.openSession();
    expect(controller.sessionActive, isTrue);
    controller.closeSession();
    expect(controller.sessionActive, isFalse);
    // A stray close never resurrects it.
    controller.closeSession();
    expect(controller.sessionActive, isFalse);
  });

  group('derived destinations', () {
    test('the bar derives the range entry and, while a session is open, the wallpaper one', () {
      expect(
        routes(derivedNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, sessionActive: false)),
        [VisibleRangePage.routeName],
      );
      expect(
        routes(derivedNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, sessionActive: true)),
        [VisibleRangePage.routeName, GroupedWallpaperPage.routeName],
      );
    });

    test('a closed session and the shared mode list only the range entry', () {
      // Removing the wallpaper entry in the editor closes the session, so the
      // editor then lists the range entry alone.
      expect(
        routes(derivedNavDestinations([all, albums], mode: GroupedWallpaperNavMode.shared, sessionActive: true)),
        [VisibleRangePage.routeName],
      );
    });

    test('shows nothing that is already the user\'s own', () {
      expect(derivedNavDestinations([all, range, wallpaper], mode: GroupedWallpaperNavMode.separateRight, sessionActive: true), isEmpty);
    });

    test('a pinned wallpaper entry is not derived again', () {
      expect(
        routes(derivedNavDestinations([all, albums, wallpaper], mode: GroupedWallpaperNavMode.separateRight, sessionActive: true)),
        [VisibleRangePage.routeName],
      );
    });
  });
}
