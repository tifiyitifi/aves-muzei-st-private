import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_session.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  AvesEntry entry(int id) => AvesEntry(
    id: id,
    uri: 'content://$id',
    path: '/album/$id.jpg',
    contentId: 100 + id,
    pageId: null,
    sourceMimeType: MimeTypes.jpeg,
    width: 100,
    height: 100,
    sourceRotationDegrees: 0,
    sizeBytes: 1,
    sourceTitle: 'photo$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  group('WallpaperSourcePickSession', () {
    group('start page', () {
      WallpaperSourcePickSession session(WallpaperSourcePickMode mode, {Set<CollectionFilter> initial = const {}}) => WallpaperSourcePickSession(
        mode: mode,
        onConfirm: (_) {},
        initialFilters: initial,
      );

      test('single always starts on the album list', () {
        final pick = session(WallpaperSourcePickMode.single, initial: {StoredAlbumFilter('/a', null)});
        expect(pick.startsOnAlbums, isTrue);
        pick.dispose();
      });

      test('filters without a user filter start on the album list', () {
        final pick = session(WallpaperSourcePickMode.filters);
        expect(pick.startsOnAlbums, isTrue, reason: 'all photos is not a set worth opening as a grid');
        expect(pick.mediaSetFilters, {MimeFilter.image});
        pick.dispose();
      });

      test('the implicit photo restriction alone is not a filter set', () {
        final pick = session(WallpaperSourcePickMode.filters, initial: {MimeFilter.image});
        expect(pick.startsOnAlbums, isTrue);
        pick.dispose();
      });

      test('filters with a user filter open the media set', () {
        final album = StoredAlbumFilter('/a', null);
        final pick = session(WallpaperSourcePickMode.filters, initial: {album});
        expect(pick.startsOnAlbums, isFalse);
        expect(pick.mediaSetFilters, contains(album));
        pick.dispose();
      });
    });

    test('filters mode returns the set without the implicit photo restriction', () {
      WallpaperSourcePickResult? result;
      final session = WallpaperSourcePickSession(
        mode: WallpaperSourcePickMode.filters,
        onConfirm: (value) => result = value,
      );

      session.confirmFilters({MimeFilter.image, FavouriteFilter.instance});

      expect(result, isA<WallpaperSourcePickFiltersResult>());
      expect((result! as WallpaperSourcePickFiltersResult).filters, {FavouriteFilter.instance});
      session.dispose();
    });

    test('single mode returns the picked entry only after a pick', () {
      WallpaperSourcePickResult? result;
      final session = WallpaperSourcePickSession(
        mode: WallpaperSourcePickMode.single,
        onConfirm: (value) => result = value,
      );

      session.confirmPicked();
      expect(result, isNull, reason: 'nothing was picked');

      final picked = entry(7);
      session.pick(picked);
      expect(session.pickedEntryNotifier.value, 7);
      session.confirmPicked();

      expect(result, isA<WallpaperSourcePickEntryResult>());
      expect((result! as WallpaperSourcePickEntryResult).entry, picked);
      session.dispose();
    });

    test('filters mode ignores an entry confirmation', () {
      WallpaperSourcePickResult? result;
      final session = WallpaperSourcePickSession(
        mode: WallpaperSourcePickMode.filters,
        onConfirm: (value) => result = value,
      );

      session.pick(entry(1));
      session.confirmPicked();

      expect(result, isNull);
      session.dispose();
    });
  });

  group('album editing', () {
    final a = StoredAlbumFilter('/a', null);
    final b = StoredAlbumFilter('/b', null);
    final c = StoredAlbumFilter('/c', null);

    WallpaperSourcePickSession session({Set<CollectionFilter> initial = const {}}) => WallpaperSourcePickSession(
      mode: WallpaperSourcePickMode.filters,
      onConfirm: (_) {},
      initialFilters: initial,
    );

    test('opening an album keeps the other conditions of the set', () {
      final pick = session(initial: {a, FavouriteFilter.instance});

      expect(pick.augmentFilters({b}), {b, FavouriteFilter.instance, MimeFilter.image});
      pick.dispose();
    });

    test('opening an album union keeps the other conditions too', () {
      final pick = session(initial: {a, FavouriteFilter.instance});

      final filters = pick.augmentFilters({
        SetOrFilter({b, c}),
      });

      expect(filters, contains(FavouriteFilter.instance));
      expect(filters, contains(MimeFilter.image));
      expect(filters.whereType<SetOrFilter>().single.innerFilters, {b, c});
      pick.dispose();
    });

    test('opening a non-album scope does not carry the old conditions', () {
      final pick = session(initial: {a, FavouriteFilter.instance});

      expect(pick.augmentFilters({FavouriteFilter.instance}), {FavouriteFilter.instance, MimeFilter.image});
      pick.dispose();
    });

    test('a condition the user removed stops following the album', () {
      final pick = session(initial: {a, FavouriteFilter.instance});
      // The user removed the favourite chip on album A.
      pick.normalizeFilters({a, MimeFilter.image});

      expect(pick.augmentFilters({b}), {b, MimeFilter.image});
      pick.dispose();
    });
  });
}
