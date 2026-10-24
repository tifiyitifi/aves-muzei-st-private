import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WallpaperArtwork', () {
    const artwork = WallpaperArtwork(
      entryId: 7,
      uri: 'content://media/external/images/media/7',
      title: 'Artwork',
      width: 2160,
      height: 3840,
      darkness: 0.42,
    );

    test('JSON round-trips the bake metrics', () {
      final decoded = WallpaperArtwork.tryFromJsonMap(artwork.toJsonMap());
      expect(decoded, artwork);
      expect(decoded!.aspectRatio, closeTo(2160 / 3840, 1e-9));
    });

    test('JSON omits the metrics when they are unknown', () {
      const plain = WallpaperArtwork(entryId: 7, uri: 'content://7');
      final json = plain.toJsonMap();
      expect(json.containsKey('width'), isFalse);
      expect(json.containsKey('height'), isFalse);
      expect(json.containsKey('darkness'), isFalse);
      expect(WallpaperArtwork.tryFromJsonMap(json), plain);
      expect(plain.aspectRatio, isNull);
    });

    test('a half-recorded size cannot describe an aspect ratio', () {
      final decoded = WallpaperArtwork.tryFromJsonMap({
        'entryId': 7,
        'uri': 'content://7',
        'width': 2160,
      });
      expect(decoded!.width, isNull);
      expect(decoded.height, isNull);
      expect(decoded.aspectRatio, isNull);
    });

    test('darkness is clamped and ignores non-finite values', () {
      expect(WallpaperArtwork.tryFromJsonMap({'entryId': 1, 'uri': 'u', 'darkness': 2})!.darkness, 1);
      expect(WallpaperArtwork.tryFromJsonMap({'entryId': 1, 'uri': 'u', 'darkness': -1})!.darkness, 0);
      expect(WallpaperArtwork.tryFromJsonMap({'entryId': 1, 'uri': 'u', 'darkness': double.nan})!.darkness, isNull);
      expect(WallpaperArtwork.tryFromJsonMap({'entryId': 1, 'uri': 'u', 'darkness': 'dark'})!.darkness, isNull);
    });

    test('copyWith keeps the metrics unless they are replaced', () {
      final moved = artwork.copyWith(entryId: 8);
      expect(moved.width, artwork.width);
      expect(moved.height, artwork.height);
      expect(moved.darkness, artwork.darkness);
    });
  });
}
