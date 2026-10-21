import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The media-set slot: the bottom bar's collection item returns to the view the
/// slot was showing (an album opened from the albums page) instead of resetting
/// the whole library behind the user's back.
void main() {
  final album = StoredAlbumFilter('/a', null);
  final video = MimeFilter.video;

  tearDown(mediaSetTab.clear);

  group('MediaSetTab', () {
    test('an empty slot opens the whole library', () {
      expect(MediaSetTab().filters, isNull);
    });

    test('remembers the album the slot showed', () {
      final tab = MediaSetTab();
      tab.note(routeFilters: {album}, currentFilters: () => {album});
      expect(tab.filters, {album});
    });

    test('a cleared view reopens the whole library', () {
      final tab = MediaSetTab();
      // The clear action at the end of the filter row dropped the album, so the
      // slot is the whole library now: returning must not resurrect it.
      tab.note(routeFilters: {album}, currentFilters: () => <CollectionFilter>{});
      expect(tab.filters, isEmpty);
    });

    test('a chip added inside the view keeps the scope it was opened with', () {
      final tab = MediaSetTab();
      tab.note(routeFilters: {album}, currentFilters: () => {album, video});
      expect(tab.filters, {album}, reason: 'the scope identity stays the album, so its retained lens is reused');
    });

    test('the last view wins', () {
      final tab = MediaSetTab();
      tab.note(routeFilters: {album}, currentFilters: () => {album});
      tab.note(routeFilters: {}, currentFilters: () => {});
      expect(tab.filters, isEmpty);
    });
  });

  group('AvesNavItem', () {
    test('a collection destination that names no filters opens the remembered view', () {
      mediaSetTab.note(routeFilters: {album}, currentFilters: () => {album});
      expect(const AvesNavItem(route: CollectionPage.routeName).effectiveFilters, {album});
    });

    test('a destination that names its filters always opens them', () {
      mediaSetTab.note(routeFilters: {album}, currentFilters: () => {album});
      expect(AvesNavItem(route: CollectionPage.routeName, filters: {video}).effectiveFilters, {video});
    });

    test('a destination with nothing remembered opens the whole library', () {
      expect(const AvesNavItem(route: CollectionPage.routeName).effectiveFilters, isNull);
    });
  });

  group('isDestinationView', () {
    test("a destination's own view is not the slot's", () {
      expect(
        isDestinationView(
          {video},
          [
            {video},
          ],
        ),
        isTrue,
        reason: 'visiting the video item must not hijack the tab',
      );
      expect(
        isDestinationView(
          {album},
          [
            {video},
          ],
        ),
        isFalse,
      );
      expect(isDestinationView({album}, [null]), isFalse, reason: 'the media-set item declares no filters of its own');
      expect(
        isDestinationView(<CollectionFilter>{}, [
          {video},
        ]),
        isFalse,
      );
    });
  });
}
