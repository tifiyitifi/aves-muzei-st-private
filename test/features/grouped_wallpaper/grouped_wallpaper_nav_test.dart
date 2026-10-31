import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
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

  test('the default mode puts the wallpaper right of the visible range', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: defaultGroupedWallpaperNavMode, entryClosed: false)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName, GroupedWallpaperPage.routeName],
    );
  });

  test('separateLeft puts it left of the visible range', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateLeft, entryClosed: false)),
      [CollectionPage.routeName, AlbumListPage.routeName, GroupedWallpaperPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('the entry follows the range entry wherever the user moved it', () {
    expect(
      routes(withWallpaperNavDestinations([all, range, albums], mode: GroupedWallpaperNavMode.separateRight, entryClosed: false)),
      [CollectionPage.routeName, VisibleRangePage.routeName, GroupedWallpaperPage.routeName, AlbumListPage.routeName],
    );
  });

  test('the shared mode keeps the single shell entry', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.shared, entryClosed: false)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('a closed entry is not derived', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, entryClosed: true)),
      [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('an entry the user pinned is not duplicated', () {
    expect(
      routes(withWallpaperNavDestinations([all, wallpaper, albums], mode: GroupedWallpaperNavMode.separateRight, entryClosed: false)),
      [CollectionPage.routeName, GroupedWallpaperPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName],
    );
  });

  test('picking a photo derives nothing', () {
    expect(
      routes(withWallpaperNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, entryClosed: false, include: false)),
      [CollectionPage.routeName, AlbumListPage.routeName],
    );
  });

  test('an unknown stored mode falls back to the default', () {
    expect(groupedWallpaperNavModeFrom('nope'), defaultGroupedWallpaperNavMode);
    expect(groupedWallpaperNavModeFrom(null), defaultGroupedWallpaperNavMode);
    expect(groupedWallpaperNavModeFrom('shared'), GroupedWallpaperNavMode.shared);
  });

  test('a closed derived entry can be brought back from the range page', () {
    expect(
      canReopenWallpaperNavEntry(mode: GroupedWallpaperNavMode.separateRight, entryClosed: true, pinned: false),
      isTrue,
    );
    expect(
      canReopenWallpaperNavEntry(mode: GroupedWallpaperNavMode.separateLeft, entryClosed: true, pinned: false),
      isTrue,
    );
  });

  test('there is nothing to reopen while the entry is shown, pinned or shared', () {
    // The entry is already on the bar.
    expect(canReopenWallpaperNavEntry(mode: GroupedWallpaperNavMode.separateRight, entryClosed: false, pinned: false), isFalse);
    // A pinned entry is the user's own and is managed in the navigation editor.
    expect(canReopenWallpaperNavEntry(mode: GroupedWallpaperNavMode.separateRight, entryClosed: true, pinned: true), isFalse);
    // The shared mode has no derived entry to close.
    expect(canReopenWallpaperNavEntry(mode: GroupedWallpaperNavMode.shared, entryClosed: true, pinned: false), isFalse);
  });

  group('merged wallpaper entry', () {
    test('a shown derived entry is closed by the menu', () {
      expect(
        wallpaperNavEntryAction(mode: GroupedWallpaperNavMode.separateRight, entryClosed: false, pinned: false),
        WallpaperNavEntryAction.close,
      );
      expect(
        wallpaperNavEntryAction(mode: GroupedWallpaperNavMode.separateLeft, entryClosed: false, pinned: false),
        WallpaperNavEntryAction.close,
      );
    });

    test('a closed derived entry is opened again', () {
      expect(
        wallpaperNavEntryAction(mode: GroupedWallpaperNavMode.separateRight, entryClosed: true, pinned: false),
        WallpaperNavEntryAction.open,
      );
    });

    test('a pinned or shared entry always opens', () {
      expect(
        wallpaperNavEntryAction(mode: GroupedWallpaperNavMode.separateRight, entryClosed: false, pinned: true),
        WallpaperNavEntryAction.open,
      );
      expect(
        wallpaperNavEntryAction(mode: GroupedWallpaperNavMode.shared, entryClosed: false, pinned: false),
        WallpaperNavEntryAction.open,
      );
    });
  });

  group('derived destinations', () {
    test('lists what the bar adds beyond the user list', () {
      expect(
        routes(derivedNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, entryClosed: false)),
        [VisibleRangePage.routeName, GroupedWallpaperPage.routeName],
      );
    });

    test('shows nothing that is already the user\'s own', () {
      expect(
        derivedNavDestinations([all, range, wallpaper], mode: GroupedWallpaperNavMode.separateRight, entryClosed: false),
        isEmpty,
      );
    });

    test('keeps only the range entry while the wallpaper entry is closed', () {
      expect(
        routes(derivedNavDestinations([all, albums], mode: GroupedWallpaperNavMode.separateRight, entryClosed: true)),
        [VisibleRangePage.routeName],
      );
    });

    test('adds only the range entry in the shared mode', () {
      expect(
        routes(derivedNavDestinations([all, albums], mode: GroupedWallpaperNavMode.shared, entryClosed: false)),
        [VisibleRangePage.routeName],
      );
    });
  });
}
