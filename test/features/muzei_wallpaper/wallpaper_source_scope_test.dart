import 'package:aves/features/muzei_wallpaper/model/wallpaper_single_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
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

    test('the revision ignores the inactive kind', () {
      final photos = WallpaperSourceScope(filters: {FavouriteFilter.instance});
      final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 7);

      final photosWithOtherSingle = photos.copyWith(singleEntryId: 9);
      expect(photosWithOtherSingle.revision, photos.revision, reason: 'single data must not invalidate a My photos source');

      final singleWithOtherFilters = single.copyWith(filters: {FavouriteFilter.instance});
      expect(singleWithOtherFilters.revision, single.revision, reason: 'My photos filters must not invalidate a single source');
    });

    test('the revision follows the active kind', () {
      final a = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 7);
      final b = a.copyWith(singleEntryId: 8);
      expect(b.revision, isNot(a.revision));

      final photos = WallpaperSourceScope(filters: {FavouriteFilter.instance});
      final otherPhotos = photos.copyWith(filters: {MimeFilter.image, FavouriteFilter.instance});
      expect(otherPhotos.revision, isNot(photos.revision));
    });

    test('copyWith can clear the single id', () {
      final scope = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 4);
      expect(scope.copyWith(clearSingleEntryId: true).singleEntryId, isNull);
    });

    group('single artwork snapshot', () {
      const artwork = WallpaperSingleArtwork(
        relativePath: 'source/single.jpg',
        entryId: 7,
        mimeType: 'image/jpeg',
        title: 'photo',
        width: 400,
        height: 300,
        sizeBytes: 1234,
      );

      test('configures a single scope without a library id', () {
        final scope = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleArtwork: artwork);
        expect(scope.isConfigured, isTrue);
        expect(scope.queryFilters, contains(MimeFilter.image));
      });

      test('JSON round-trips the snapshot', () {
        final scope = WallpaperSourceScope(
          kind: WallpaperSourceKind.single,
          singleEntryId: 7,
          singleArtwork: artwork,
        );
        final decoded = WallpaperSourceScope.fromJsonString(scope.toJsonString());
        expect(decoded, scope);
        expect(decoded!.singleArtwork, artwork);
      });

      test('the snapshot survives a kind switch but is only active for single', () {
        final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 7, singleArtwork: artwork);
        final photos = single.copyWith(kind: WallpaperSourceKind.myPhotos);

        expect(photos.singleArtwork, artwork, reason: 'the copy must be there when the user switches back');
        expect(photos.activeSingleArtwork, isNull, reason: 'a my-photos view resolves the library entry, not the copy');
        expect(single.activeSingleArtwork, artwork);
      });

      test('legacy JSON without a snapshot still parses', () {
        final decoded = WallpaperSourceScope.fromJsonMap({
          'kind': 'single',
          'filters': <String>[],
          'singleEntryId': 7,
        });
        expect(decoded.singleEntryId, 7);
        expect(decoded.singleArtwork, isNull);
        expect(decoded.isConfigured, isTrue);
      });

      test('a malformed snapshot is dropped instead of failing the scope', () {
        final decoded = WallpaperSourceScope.fromJsonMap({
          'kind': 'single',
          'singleEntryId': 7,
          'singleArtwork': {'relativePath': '../escape.jpg'},
        });
        expect(decoded.singleArtwork, isNull);
        expect(decoded.singleEntryId, 7);
      });

      test('copyWith can replace or clear the snapshot', () {
        final scope = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleArtwork: artwork);
        expect(scope.copyWith(singleArtwork: artwork).singleArtwork, artwork);
        expect(scope.copyWith(clearSingleArtwork: true).singleArtwork, isNull);
      });

      test('the snapshot is part of the revision', () {
        final without = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 7);
        final withCopy = without.copyWith(singleArtwork: artwork);
        expect(withCopy.revision, isNot(without.revision));
      });
    });
  });
}
