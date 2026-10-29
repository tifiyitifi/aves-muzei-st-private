import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/settings/defaults.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar a fresh install starts with.
///
/// The four destinations are stored, so the user can move or remove them in the
/// navigation editor; the wallpaper groups' entry is derived next to the range
/// entry instead, which is what keeps it closable.
void main() {
  test('a fresh install starts with four bottom-bar destinations', () {
    final items = SettingsDefaults.bottomNavigationActions;

    expect([for (final item in items) item.route], [
      CollectionPage.routeName,
      CollectionPage.routeName,
      AlbumListPage.routeName,
      VisibleRangePage.routeName,
    ]);
    expect(items[1].filters, {FavouriteFilter.instance});
    expect(
      items.any((item) => item.route == GroupedWallpaperPage.routeName),
      isFalse,
      reason: 'the wallpaper entry is derived, never written into the settings',
    );
  });
}
