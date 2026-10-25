import 'package:aves/features/muzei_wallpaper/model/wallpaper_single_artwork.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const artwork = WallpaperSingleArtwork(
    relativePath: 'source/single.jpg',
    entryId: 42,
    mimeType: 'image/jpeg',
    title: 'A photo',
    width: 400,
    height: 300,
    rotationDegrees: 90,
    isFlipped: true,
    isAnimated: false,
    sizeBytes: 1234,
  );

  group('WallpaperSingleArtwork', () {
    test('JSON round-trips every field', () {
      final decoded = WallpaperSingleArtwork.tryFromJsonMap(artwork.toJsonMap());
      expect(decoded, artwork);
    });

    test('a missing title stays absent', () {
      const untitled = WallpaperSingleArtwork(
        relativePath: 'source/single.jpg',
        entryId: 1,
        mimeType: 'image/jpeg',
        width: 10,
        height: 10,
        sizeBytes: 1,
      );
      expect(untitled.toJsonMap(), isNot(contains('title')));
      expect(WallpaperSingleArtwork.tryFromJsonMap(untitled.toJsonMap()), untitled);
    });

    test('rejects a path escaping the wallpaper root', () {
      expect(WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'relativePath': '/etc/passwd'}), isNull);
      expect(WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'relativePath': '../outside.jpg'}), isNull);
    });

    test('rejects missing or invalid identity fields', () {
      expect(WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'entryId': 0}), isNull);
      expect(WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'mimeType': 'text/plain'}), isNull);
      expect(WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'width': 0}), isNull);
      expect(WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'height': null}), isNull);
    });

    test('rotation is normalized into 0..359', () {
      final decoded = WallpaperSingleArtwork.tryFromJsonMap({...artwork.toJsonMap(), 'rotationDegrees': 450});
      expect(decoded?.rotationDegrees, 90);
    });
  });
}
