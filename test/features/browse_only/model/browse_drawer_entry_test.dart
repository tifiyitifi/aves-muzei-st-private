import 'package:aves/features/browse_only/model/browse_drawer_entry.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/widgets/about/about_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/debug/app_debug_page.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/countries_page.dart';
import 'package:aves/widgets/filter_grids/places_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves/widgets/settings/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which drawer destinations the browse-only surface can honestly open.
///
/// Everything works once the import is done; while it runs, only the
/// destinations backed by the media store (or by no library at all) stay live.
void main() {
  test('everything is reachable once the library is organized', () {
    for (final route in [CollectionPage.routeName, TagListPage.routeName, PlaceListPage.routeName, CountryListPage.routeName]) {
      expect(browseDrawerEntryEnabled(browsing: false, route: route), isTrue, reason: route);
    }
  });

  test('the whole timeline and the folder list stay reachable while organizing', () {
    expect(browseDrawerEntryEnabled(browsing: true, route: CollectionPage.routeName), isTrue);
    expect(browseDrawerEntryEnabled(browsing: true, route: CollectionPage.routeName, filters: const []), isTrue);
    expect(browseDrawerEntryEnabled(browsing: true, route: AlbumListPage.routeName), isTrue);
  });

  test('the app pages and the file system stay reachable while organizing', () {
    for (final route in [ExplorerPage.routeName, SettingsPage.routeName, AboutPage.routeName, AppDebugPage.routeName]) {
      expect(browseDrawerEntryEnabled(browsing: true, route: route), isTrue, reason: route);
    }
  });

  test('anything narrowed by catalogued metadata is greyed while organizing', () {
    expect(browseDrawerEntryEnabled(browsing: true, route: CollectionPage.routeName, filters: {MimeFilter.video}), isFalse);
    expect(browseDrawerEntryEnabled(browsing: true, route: CollectionPage.routeName, filters: {FavouriteFilter.instance}), isFalse);
    expect(browseDrawerEntryEnabled(browsing: true, route: CollectionPage.routeName, filters: {TrashFilter.instance}), isFalse);
    for (final route in [CountryListPage.routeName, PlaceListPage.routeName, TagListPage.routeName]) {
      expect(browseDrawerEntryEnabled(browsing: true, route: route), isFalse, reason: route);
    }
  });

  test('an unknown destination is left alone', () {
    expect(browseDrawerEntryEnabled(browsing: true, route: '/some-future-page'), isTrue);
  });
}
