import 'package:aves/features/visible_range/view/visible_range_nav.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_display.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The visible-range destination is appended to the user's own bar, never
/// written into their settings and never duplicated.
void main() {
  const mediaSet = AvesNavItem(route: CollectionPage.routeName);
  const albums = AvesNavItem(route: AlbumListPage.routeName);
  const visibleRange = AvesNavItem(route: VisibleRangePage.routeName);

  test('appends the destination at the far right', () {
    final items = withVisibleRangeDestination([mediaSet, albums]);
    expect(items.map((item) => item.route), [CollectionPage.routeName, AlbumListPage.routeName, VisibleRangePage.routeName]);
  });

  test('does not duplicate a destination the user already added', () {
    final items = withVisibleRangeDestination([mediaSet, visibleRange, albums]);
    expect(items.map((item) => item.route), [CollectionPage.routeName, VisibleRangePage.routeName, AlbumListPage.routeName]);
    expect(items.where((item) => item.route == VisibleRangePage.routeName), hasLength(1));
  });

  test('leaves the list untouched when the surface hides the destination', () {
    final items = withVisibleRangeDestination([mediaSet, albums], include: false);
    expect(items.map((item) => item.route), [CollectionPage.routeName, AlbumListPage.routeName]);
  });

  test('does not mutate the input list', () {
    final configured = [mediaSet, albums];
    withVisibleRangeDestination(configured);
    expect(configured, hasLength(2));
  });

  test('the destination keeps the old scenario shield', () {
    expect(NavigationDisplay.getPageIcon(VisibleRangePage.routeName), AIcons.visibleRange);
    expect(AIcons.visibleRange, Symbols.security);
  });
}
