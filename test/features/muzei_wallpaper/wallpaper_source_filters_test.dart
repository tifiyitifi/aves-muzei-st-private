import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_filters.dart';
import 'package:aves/model/filters/favourite.dart';
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

  group('normalizeWallpaperFilters', () {
    test('an empty set becomes the all-photos set', () {
      expect(normalizeWallpaperFilters(const {}), {MimeFilter.image});
    });

    test('video restrictions are dropped in both directions', () {
      final normalized = normalizeWallpaperFilters({
        FavouriteFilter.instance,
        MimeFilter.video,
        MimeFilter(MimeTypes.anyVideo, reversed: true),
        MimeFilter('video/mp4'),
        MimeFilter('video/mp4', reversed: true),
      });
      expect(normalized, {FavouriteFilter.instance, MimeFilter.image});
    });

    test('an image subtype the user chose is kept and needs no wildcard', () {
      final png = MimeFilter(MimeTypes.png);
      final normalized = normalizeWallpaperFilters({FavouriteFilter.instance, png});
      expect(normalized, {FavouriteFilter.instance, png});
      expect(normalized, isNot(contains(MimeFilter.image)));
    });

    test('a negated image restriction is dropped', () {
      final normalized = normalizeWallpaperFilters({
        MimeFilter(MimeTypes.anyImage, reversed: true),
      });
      expect(normalized, {MimeFilter.image});
    });

    test('non-MIME filters are untouched', () {
      final normalized = normalizeWallpaperFilters({FavouriteFilter.instance});
      expect(normalized, {FavouriteFilter.instance, MimeFilter.image});
    });
  });

  group('withoutWallpaperPhotoRestriction', () {
    test('drops only the implicit wildcard', () {
      final png = MimeFilter(MimeTypes.png);
      final filters = withoutWallpaperPhotoRestriction({MimeFilter.image, png, FavouriteFilter.instance});
      expect(filters, {png, FavouriteFilter.instance});
    });
  });
}
