import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves/widgets/map/map_page.dart';

/// Top-level destinations that can be reopened after the process dies.
///
/// Only pages that need no external intent are listed: a viewer, a search, the
/// explorer or a settings sub-page either take a required argument or return to
/// a parent that is already restored. Restoring the media set under a viewer is
/// enough to bring the user back to what they were browsing.
const Set<String> restorableSessionRoutes = {
  CollectionPage.routeName,
  AlbumListPage.routeName,
  TagListPage.routeName,
  MapPage.routeName,
  MuzeiWallpaperPage.routeName,
  VisibleRangePage.routeName,
  GroupedWallpaperPage.routeName,
};

/// Restorable pages that are normally pushed over another page.
///
/// Restoring one of these on its own leaves the navigator with nothing to go
/// back to, so the snapshot also records the page it was opened from.
const Set<String> pushedRestorableSessionRoutes = {
  MuzeiWallpaperPage.routeName,
  // The wallpaper page is always opened over another page: its own bottom-bar
  // entry pushes it, and in the shared mode the range shell renders it behind
  // the range entry. Without the base, restoring it would have no page to return
  // to, and the snapshot would only remember the page underneath instead.
  GroupedWallpaperPage.routeName,
};
