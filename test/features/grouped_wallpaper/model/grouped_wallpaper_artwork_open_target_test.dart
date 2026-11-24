import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_artwork_open_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the artwork title opens in the viewer by default', () {
    expect(GroupedWallpaperArtworkOpenTarget.tryParse(null), GroupedWallpaperArtworkOpenTarget.viewer);
  });

  test('the artwork title target round-trips by enum name', () {
    for (final target in GroupedWallpaperArtworkOpenTarget.values) {
      expect(GroupedWallpaperArtworkOpenTarget.tryParse(target.name), target);
    }
  });

  test('an unknown artwork title target falls back to the viewer', () {
    expect(GroupedWallpaperArtworkOpenTarget.tryParse('unknown'), GroupedWallpaperArtworkOpenTarget.viewer);
  });
}
