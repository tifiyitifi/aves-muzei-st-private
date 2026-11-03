import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-surface framing value: defaults, persistence and unknown values.
void main() {
  test('the default framing leaves the photo untouched', () {
    const framing = WallpaperFraming();
    expect(framing.rotation, WallpaperRotation.off);
    expect(framing.fit, WallpaperImageFit.fill);
    expect(framing.isDefault, isTrue);
  });

  test('JSON round-trips by enum name', () {
    const framing = WallpaperFraming(rotation: WallpaperRotation.random, fit: WallpaperImageFit.stretch);
    final decoded = WallpaperFraming.fromJsonMap(framing.toJsonMap());
    expect(decoded, framing);
    expect(framing.toJsonMap(), {'rotation': 'random', 'fit': 'stretch'});
  });

  test('missing and unknown values fall back to the defaults', () {
    expect(WallpaperFraming.fromJsonMap(null), const WallpaperFraming());
    expect(WallpaperFraming.fromJsonMap(const {}), const WallpaperFraming());
    expect(WallpaperFraming.fromJsonMap(const {'rotation': 'sideways', 'fit': 'zoom'}), const WallpaperFraming());
  });

  test('copyWith changes one axis at a time', () {
    const framing = WallpaperFraming(rotation: WallpaperRotation.clockwise);
    expect(framing.copyWith(fit: WallpaperImageFit.fit).rotation, WallpaperRotation.clockwise);
    expect(framing.copyWith(rotation: WallpaperRotation.off).fit, WallpaperImageFit.fill);
    expect(framing.copyWith().isDefault, isFalse);
  });
}
