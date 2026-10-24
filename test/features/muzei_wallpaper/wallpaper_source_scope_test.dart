import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  // `SetOrFilter` sorts its members by label, which resolves the POSIX
  // `p.Context` registered by the test services.
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  group('WallpaperSourceScope', () {
    test('empty myPhotos scope means all photos and is configured', () {
      final scope = WallpaperSourceScope();
      expect(scope.kind, WallpaperSourceKind.myPhotos);
      expect(scope.isConfigured, isTrue);
      expect(scope.filters, isEmpty);
      expect(scope.queryFilters, contains(MimeFilter.image));
    });

    test('single scope is configured only with a positive entry id', () {
      expect(WallpaperSourceScope(kind: WallpaperSourceKind.single).isConfigured, isFalse);
      expect(WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 0).isConfigured, isFalse);
      expect(WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 42).isConfigured, isTrue);
    });

    test('queryFilters always forces the image MIME restriction', () {
      final scope = WallpaperSourceScope(
        filters: {FavouriteFilter.instance, MimeFilter.video},
      );
      expect(scope.queryFilters, contains(MimeFilter.image));
      expect(scope.queryFilters, contains(FavouriteFilter.instance));
      expect(scope.queryFilters, contains(MimeFilter.video));
    });

    test('JSON round-trips filters and the single id', () {
      final scope = WallpaperSourceScope(
        kind: WallpaperSourceKind.single,
        filters: {FavouriteFilter.instance, MimeFilter.image},
        singleEntryId: 7,
      );
      final decoded = WallpaperSourceScope.fromJsonString(scope.toJsonString());
      expect(decoded, scope);
      expect(decoded!.sortedFilterJson, scope.sortedFilterJson);
    });

    test('fromJsonString tolerates malformed JSON and unknown filters', () {
      expect(WallpaperSourceScope.fromJsonString(null), isNull);
      expect(WallpaperSourceScope.fromJsonString(''), isNull);
      expect(WallpaperSourceScope.fromJsonString('{'), isNull);

      final decoded = WallpaperSourceScope.fromJsonMap({
        'kind': 'myPhotos',
        'filters': [
          '{"type":"does-not-exist"}',
          MimeFilter.image.toJsonString(),
        ],
      });
      expect(decoded.filters, {MimeFilter.image});
    });

    test('revision is stable for equal content and changes with content', () {
      final a = WallpaperSourceScope(filters: {MimeFilter.image});
      final b = WallpaperSourceScope(filters: {MimeFilter.image});
      expect(a.revision, b.revision);

      final withFavourite = a.copyWith(filters: {MimeFilter.image, FavouriteFilter.instance});
      expect(withFavourite.revision, isNot(a.revision));

      final single = a.copyWith(kind: WallpaperSourceKind.single, singleEntryId: 1);
      expect(single.revision, isNot(a.revision));
    });

    test('filter order does not affect the revision', () {
      final a = WallpaperSourceScope(filters: {MimeFilter.image, FavouriteFilter.instance});
      final b = WallpaperSourceScope(filters: {FavouriteFilter.instance, MimeFilter.image});
      expect(a.revision, b.revision);
    });

    test('copyWith can clear the single id', () {
      final scope = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 4);
      expect(scope.copyWith(clearSingleEntryId: true).singleEntryId, isNull);
    });

    group('filtersForAlbums', () {
      test('no album means the all-photos scope', () {
        expect(WallpaperSourceScope.filtersForAlbums(const []), isEmpty);
      });

      test('a single album stays a plain album filter', () {
        final album = StoredAlbumFilter('/one', null);
        expect(WallpaperSourceScope.filtersForAlbums([album]), {album});
      });

      test('multiple albums are unioned with SetOrFilter', () {
        final a = StoredAlbumFilter('/a', null);
        final b = StoredAlbumFilter('/b', null);
        final filters = WallpaperSourceScope.filtersForAlbums([a, b]);

        expect(filters, hasLength(1));
        final union = filters.single;
        expect(union, isA<SetOrFilter>());
        expect((union as SetOrFilter).innerFilters, {a, b});
      });

      test('duplicate albums collapse and keep the plain filter', () {
        final album = StoredAlbumFilter('/one', null);
        expect(WallpaperSourceScope.filtersForAlbums([album, album]), {album});
      });

      test('the implicit image restriction still applies to a union', () {
        final scope = WallpaperSourceScope(
          filters: WallpaperSourceScope.filtersForAlbums([
            StoredAlbumFilter('/a', null),
            StoredAlbumFilter('/b', null),
          ]),
        );
        expect(scope.queryFilters, contains(MimeFilter.image));
      });
    });
  });
}
