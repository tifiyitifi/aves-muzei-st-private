import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WallpaperEffects', () {
    test('defaults match Muzei', () {
      const effects = WallpaperEffects();
      expect(effects.blur, WallpaperEffects.defaultBlur);
      expect(effects.dim, WallpaperEffects.defaultDim);
      expect(effects.grey, WallpaperEffects.defaultGrey);
      expect(effects.isIdentity, isFalse);
    });

    test('fromJsonMap clamps out-of-range values', () {
      final effects = WallpaperEffects.fromJsonMap({
        'blur': -10,
        'dim': 999,
        'grey': 501,
      });
      expect(effects.blur, 0);
      expect(effects.dim, WallpaperEffects.maxDim);
      expect(effects.grey, WallpaperEffects.maxGrey);
    });

    test('copyWith clamps', () {
      const effects = WallpaperEffects();
      expect(effects.copyWith(blur: -1).blur, 0);
      expect(effects.copyWith(dim: 300).dim, WallpaperEffects.maxDim);
      expect(effects.copyWith(grey: 900).grey, WallpaperEffects.maxGrey);
    });

    test('sigma follows the screen height and downscale', () {
      const effects = WallpaperEffects();
      // 2400 * 250 * 0.0001 = 60px radius, sigma = 30.
      expect(effects.sigmaFor(2400), closeTo(30, 1e-9));
      expect(effects.sigmaFor(2400, downscale: 4), closeTo(7.5, 1e-9));
      expect(const WallpaperEffects(blur: 0).sigmaFor(2400), 0);
    });

    test('dim alpha follows the darkness curve', () {
      const effects = WallpaperEffects(dim: 128);
      expect(effects.dimAlpha(0), 64);
      expect(effects.dimAlpha(0.25), 96);
      expect(effects.dimAlpha(1), 128);
      expect(effects.dimAlpha(-1), 64);
      expect(effects.dimAlpha(2), 128);
    });

    test('desaturation matrix is identity at grey 0', () {
      const effects = WallpaperEffects(grey: 0);
      expect(effects.desaturationMatrix, [
        1.0, 0.0, 0.0, 0.0, 0.0, //
        0.0, 1.0, 0.0, 0.0, 0.0, //
        0.0, 0.0, 1.0, 0.0, 0.0, //
        0.0, 0.0, 0.0, 1.0, 0.0, //
      ]);
    });

    test('desaturation matrix is fully grey at the top of the scale', () {
      const effects = WallpaperEffects(grey: 500);
      final matrix = effects.desaturationMatrix;
      expect(matrix[0], closeTo(0.299, 1e-9));
      expect(matrix[1], closeTo(0.587, 1e-9));
      expect(matrix[2], closeTo(0.114, 1e-9));
      expect(matrix[5], closeTo(0.299, 1e-9));
      expect(matrix[12], closeTo(0.114, 1e-9));
      expect(matrix[18], 1.0);
      expect(matrix[19], 0.0);
    });

    test('JSON round-trips', () {
      const effects = WallpaperEffects(blur: 20, dim: 30, grey: 40);
      expect(WallpaperEffects.fromJsonMap(effects.toJsonMap()), effects);
    });
  });

  group('WallpaperEffectsConfig', () {
    test('link uses home values for the lock surface', () {
      const config = WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 10),
        lock: WallpaperEffects(blur: 400),
        link: true,
      );
      expect(config.effectiveLock.blur, 10);

      final unlinked = config.copyWith(link: false);
      expect(unlinked.effectiveLock.blur, 400);
    });

    test('JSON round-trips with defaults for missing surfaces', () {
      const config = WallpaperEffectsConfig(home: WallpaperEffects(dim: 10));
      final decoded = WallpaperEffectsConfig.fromJsonMap(config.toJsonMap());
      expect(decoded, config);
      expect(WallpaperEffectsConfig.fromJsonMap(const {}), const WallpaperEffectsConfig());
    });
  });
}
