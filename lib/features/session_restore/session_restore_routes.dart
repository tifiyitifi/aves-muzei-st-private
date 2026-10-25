import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
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
};
