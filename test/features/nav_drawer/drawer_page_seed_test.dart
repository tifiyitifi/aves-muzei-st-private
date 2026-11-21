import 'package:aves/features/nav_drawer/model/drawer_page_keys.dart';
import 'package:aves/features/nav_drawer/services/drawer_page_seed.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/countries_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves_model/aves_model.dart';import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common.dart';

/// The one-time backfill of the visible-range entry.
///
/// Before the fork pages became editable, the range was a fixed drawer tile, so
/// a stored page list lacks it; the backfill must restore it once and then leave
/// the user's own removals alone.
void main() {
  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  setUp(() async {
    await setUpServices();
    // `setUpServices` clears the settings store, which clears the same
    // `SharedPreferences` file; assert the marker really starts unset.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DrawerPageKeys.forkPagesInitialized), isNull);
  });

  bool? marker(SharedPreferences prefs) => prefs.getBool(DrawerPageKeys.forkPagesInitialized);

  test('a list saved before the fork pages became editable gets the visible range back', () async {
    settings.drawerPageBookmarks = [
      AlbumListPage.routeName,
      CountryListPage.routeName,
      TagListPage.routeName,
      ExplorerPage.routeName,
    ];
    expect(settings.drawerPageBookmarks, isNot(contains(VisibleRangePage.routeName)));

    await DrawerPageSeed().runIfNeeded(useTvLayout: false);

    expect(settings.drawerPageBookmarks, [
      AlbumListPage.routeName,
      CountryListPage.routeName,
      TagListPage.routeName,
      VisibleRangePage.routeName,
      ExplorerPage.routeName,
    ]);
    expect(marker(await SharedPreferences.getInstance()), isTrue);
  });

  test('a fresh install keeps the defaults and is only marked', () async {
    expect(settings.getStringList(SettingKeys.drawerPageBookmarksKey), isNull);

    await DrawerPageSeed().runIfNeeded(useTvLayout: false);

    // The defaults already carry the entry, so writing a list would only pin it.
    expect(settings.getStringList(SettingKeys.drawerPageBookmarksKey), isNull);
    expect(marker(await SharedPreferences.getInstance()), isTrue);
  });

  test('a list the editor already saved is a decision and stays alone', () async {
    await DrawerPageSeed().markConfigured();
    settings.drawerPageBookmarks = const [AlbumListPage.routeName];

    await DrawerPageSeed().runIfNeeded(useTvLayout: false);

    expect(settings.drawerPageBookmarks, const [AlbumListPage.routeName]);
  });

  test('the TV rail keeps its own list', () async {
    settings.drawerPageBookmarks = const [AlbumListPage.routeName, ExplorerPage.routeName];

    await DrawerPageSeed().runIfNeeded(useTvLayout: true);

    expect(settings.drawerPageBookmarks, const [AlbumListPage.routeName, ExplorerPage.routeName]);
    expect(marker(await SharedPreferences.getInstance()), isTrue);
  });

  test('the marking is idempotent', () async {
    await DrawerPageSeed().markConfigured();
    await DrawerPageSeed().markConfigured();

    expect(marker(await SharedPreferences.getInstance()), isTrue);
  });

  group('insertion', () {
    test('goes before Explorer', () {
      expect(
        withLegacyVisibleRange([AlbumListPage.routeName, ExplorerPage.routeName]),
        [AlbumListPage.routeName, VisibleRangePage.routeName, ExplorerPage.routeName],
      );
    });

    test('goes last when the list has no Explorer', () {
      expect(
        withLegacyVisibleRange([AlbumListPage.routeName]),
        [AlbumListPage.routeName, VisibleRangePage.routeName],
      );
    });

    test('is idempotent', () {
      const pages = [AlbumListPage.routeName, VisibleRangePage.routeName, ExplorerPage.routeName];
      expect(withLegacyVisibleRange(pages), pages);
    });
  });
}
