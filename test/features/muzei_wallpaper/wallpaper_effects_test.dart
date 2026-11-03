import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WallpaperEffects', () {
    test('defaults leave the artwork untouched, deliberately unlike Muzei', () {
      const effects = WallpaperEffects();
      expect(effects.blur, 0);
      expect(effects.dim, 0);
      expect(effects.grey, 0);
      expect(effects.isIdentity, isTrue, reason: 'the photo is shown as it is until the user opts into effects');
    });

    test('Muzei defaults stay available as a preset', () {
      expect(WallpaperEffects.muzeiDefaults.blur, 250);
      expect(WallpaperEffects.muzeiDefaults.dim, 128);
      expect(WallpaperEffects.muzeiDefaults.grey, 0);
      expect(WallpaperEffects.muzeiDefaults.isIdentity, isFalse);
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
      const effects = WallpaperEffects.muzeiDefaults;
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

    test('the scroll effect travels with the group config', () {
      const config = WallpaperEffectsConfig(homeScrollEffect: false);
      final decoded = WallpaperEffectsConfig.fromJsonMap(config.toJsonMap());
      expect(decoded.homeScrollEffect, isFalse);
      expect(decoded, config);
    });

    test('a config written before the scroll switch takes the legacy value', () {
      // Groups used to share one app-wide switch; reading a group that never
      // stored its own value keeps the user's existing choice.
      expect(WallpaperEffectsConfig.fromJsonMap(const {}, legacyScrollEffect: false).homeScrollEffect, isFalse);
      expect(WallpaperEffectsConfig.fromJsonMap(const {}, legacyScrollEffect: true).homeScrollEffect, isTrue);
      // A stored value always wins over the legacy one.
      final json = const WallpaperEffectsConfig(homeScrollEffect: false).toJsonMap();
      expect(WallpaperEffectsConfig.fromJsonMap(json, legacyScrollEffect: true).homeScrollEffect, isFalse);
    });

    test('applyTo writes the edited surface only, unless the link is on', () {
      const config = WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 10),
        lock: WallpaperEffects(blur: 40),
      );
      const value = WallpaperEffects(blur: 300);

      final home = config.applyTo(onLock: false, value: value);
      expect(home.home, value);
      expect(home.lock, config.lock);

      final lock = config.applyTo(onLock: true, value: value);
      expect(lock.lock, value);
      expect(lock.home, config.home);

      final linked = config.withLink(linked: true, fromLock: false).applyTo(onLock: true, value: value);
      expect(linked.home, value, reason: 'a linked surface is one setting');
      expect(linked.effectiveLock, value);
    });

    test('withLink copies the edited surface onto the other', () {
      const config = WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 10),
        lock: WallpaperEffects(blur: 40),
      );

      final fromHome = config.withLink(linked: true, fromLock: false);
      expect(fromHome.home.blur, 10);
      expect(fromHome.lock.blur, 10);
      expect(fromHome.link, isTrue);

      final fromLock = config.withLink(linked: true, fromLock: true);
      expect(fromLock.home.blur, 40);
      expect(fromLock.lock.blur, 40);

      final unlinked = fromHome.withLink(linked: false, fromLock: false);
      expect(unlinked.link, isFalse);
      expect(unlinked.home.blur, 10);
      expect(unlinked.lock.blur, 10);
    });

    test('framing is stored per surface and is not linked', () {
      const config = WallpaperEffectsConfig(
        framingHome: WallpaperFraming(rotation: WallpaperRotation.clockwise, fit: WallpaperImageFit.fit),
        framingLock: WallpaperFraming(rotation: WallpaperRotation.random, fit: WallpaperImageFit.stretch),
      );

      // The link toggle is about the effect sliders; each surface judges its own
      // orientation, so framing is deliberately not copied.
      final linked = config.withLink(linked: true, fromLock: true);
      expect(linked.framingHome, config.framingHome);
      expect(linked.framingLock, config.framingLock);

      final edited = config.withFraming(onLock: true, value: const WallpaperFraming(rotation: WallpaperRotation.counterClockwise));
      expect(edited.framingHome, config.framingHome);
      expect(edited.framingLock.rotation, WallpaperRotation.counterClockwise);
      expect(edited.framingLock.fit, WallpaperImageFit.fill, reason: 'the edit replaces the whole framing value');
    });

    test('framing survives the config JSON', () {
      const config = WallpaperEffectsConfig(
        framingHome: WallpaperFraming(rotation: WallpaperRotation.clockwise, fit: WallpaperImageFit.fit),
        framingLock: WallpaperFraming(rotation: WallpaperRotation.random, fit: WallpaperImageFit.stretch),
      );
      expect(WallpaperEffectsConfig.fromJsonMap(config.toJsonMap()), config);
      // A config written before framing existed reads the identity framing.
      expect(WallpaperEffectsConfig.fromJsonMap(const {}).framingHome, const WallpaperFraming());
      expect(WallpaperEffectsConfig.fromJsonMap(const {}).framingLock, const WallpaperFraming());
    });

    test('a group without a stored framing reads the given default', () {
      const defaultFraming = WallpaperFraming(rotation: WallpaperRotation.random);
      final decoded = WallpaperEffectsConfig.fromJsonMap(const {}, defaultFraming: defaultFraming);
      expect(decoded.framingHome, defaultFraming);
      expect(decoded.framingLock, defaultFraming);
      // A stored framing still wins over the default.
      const stored = WallpaperFraming(rotation: WallpaperRotation.clockwise, fit: WallpaperImageFit.stretch);
      final withStored = WallpaperEffectsConfig.fromJsonMap(const WallpaperEffectsConfig(framingHome: stored).toJsonMap(), defaultFraming: defaultFraming);
      expect(withStored.framingHome, stored);
    });

    test('an unset scroll effect follows the device, a set one does not', () {
      const automatic = WallpaperEffectsConfig();
      expect(automatic.scrollEffectIsAuto, isTrue);
      expect(automatic.resolvedHomeScrollEffect(pans: true), isTrue);
      expect(automatic.resolvedHomeScrollEffect(pans: false), isFalse);

      // A manual choice persists, even when the launcher cannot pan any more.
      const chosen = WallpaperEffectsConfig(homeScrollEffect: true);
      expect(chosen.scrollEffectIsAuto, isFalse);
      expect(chosen.resolvedHomeScrollEffect(pans: false), isTrue);

      // A stored `null` is "automatic", not "missing": the legacy switch must not
      // claim it.
      final json = automatic.toJsonMap();
      final decoded = WallpaperEffectsConfig.fromJsonMap(json, legacyScrollEffect: false);
      expect(decoded.homeScrollEffect, isNull);
      expect(decoded.scrollEffectIsAuto, isTrue);
    });

    test('the rotation threshold round-trips and stays in range', () {
      const config = WallpaperEffectsConfig(rotationThreshold: 1.5);
      expect(WallpaperEffectsConfig.fromJsonMap(config.toJsonMap()).rotationThreshold, 1.5);
      // A config written before the slider existed keeps the tuned default.
      expect(WallpaperEffectsConfig.fromJsonMap(const {}).rotationThreshold, WallpaperEffectsConfig.defaultRotationThreshold);

      expect(WallpaperEffectsConfig.clampRotationThreshold(.5), WallpaperEffectsConfig.minRotationThreshold);
      expect(WallpaperEffectsConfig.clampRotationThreshold(3), WallpaperEffectsConfig.maxRotationThreshold);
      expect(WallpaperEffectsConfig.clampRotationThreshold(double.nan), WallpaperEffectsConfig.defaultRotationThreshold);
      // copyWith sanitizes too, so a slider cannot store an out-of-range value.
      expect(const WallpaperEffectsConfig().copyWith(rotationThreshold: 9).rotationThreshold, WallpaperEffectsConfig.maxRotationThreshold);
    });
  });
}
