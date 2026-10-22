import 'package:aves/model/filters/filters.dart';
import 'package:aves/widgets/about/about_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/debug/app_debug_page.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/countries_page.dart';
import 'package:aves/widgets/filter_grids/places_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves/widgets/settings/settings_page.dart';

/// Whether a drawer destination can be opened while the library is still being
/// organized.
///
/// The browser answers from the media store alone, so it can serve the whole
/// timeline, the folder list, the file system and the app's own pages. A
/// destination that narrows by catalogued metadata — videos, favourites, a tag,
/// a place, a country, the bin, a bookmarked album — would open a collection
/// holding only the rows the import has written so far, which reads as an empty
/// library rather than as a paused one. Those are greyed until the handoff; the
/// drawer keeps every entry, so the bar does not rearrange itself mid-import.
///
/// An unknown route stays enabled: greying a page this fork does not know about
/// would hide a feature that may work perfectly well.
bool browseDrawerEntryEnabled({
  required bool browsing,
  required String route,
  Iterable<CollectionFilter?>? filters,
}) {
  if (!browsing) return true;
  switch (route) {
    case CollectionPage.routeName:
      // Only the media set (no filters) is the whole timeline the browser has.
      return filters == null || filters.whereType<CollectionFilter>().isEmpty;
    case AlbumListPage.routeName:
    case ExplorerPage.routeName:
    case SettingsPage.routeName:
    case AboutPage.routeName:
    case AppDebugPage.routeName:
      return true;
    case CountryListPage.routeName:
    case PlaceListPage.routeName:
    case TagListPage.routeName:
      return false;
    default:
      return true;
  }
}
