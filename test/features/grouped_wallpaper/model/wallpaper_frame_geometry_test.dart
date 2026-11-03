import 'dart:ui' show Size;

import 'package:aves/features/grouped_wallpaper/model/wallpaper_frame_geometry.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-photo rotation decision and the resolved geometry it feeds the baker.
void main() {
  group('wallpaperNeedsRotation', () {
    const portrait = Size(1080, 2400);
    const landscape = Size(2400, 1080);

    test('a landscape photo on a portrait screen is worth rotating', () {
      expect(wallpaperNeedsRotation(const Size(3000, 2000), portrait), isTrue);
      expect(wallpaperNeedsRotation(const Size(4000, 3000), portrait), isTrue);
    });

    test('a portrait photo on a portrait screen is left alone', () {
      expect(wallpaperNeedsRotation(const Size(2000, 3000), portrait), isFalse);
      expect(wallpaperNeedsRotation(const Size(1080, 1080), portrait), isFalse);
    });

    test('a portrait photo on a landscape screen is rotated too', () {
      expect(wallpaperNeedsRotation(const Size(2000, 3000), landscape), isTrue);
    });

    test('a mildly mismatched pair is not worth a quarter turn', () {
      // A 1.43:1 portrait photo on a mildly landscape 1.1:1 surface gains less
      // than the 44% the margin asks for, so it is left alone.
      expect(wallpaperNeedsRotation(const Size(700, 1000), const Size(1100, 1000)), isFalse);
    });

    test('a square surface never rotates anything', () {
      const square = Size(1000, 1000);
      expect(wallpaperNeedsRotation(const Size(1500, 1000), square), isFalse);
      expect(wallpaperNeedsRotation(const Size(1000, 1500), square), isFalse);
    });

    test('a nearly square photo is not worth a quarter turn', () {
      // 1.1 is below the 1.2 threshold: rotating would gain less than 44% of
      // visible area and surprise the user more than it helps.
      expect(wallpaperNeedsRotation(const Size(1100, 1000), portrait), isFalse);
      expect(wallpaperNeedsRotation(const Size(1200, 1000), portrait), isTrue);
    });

    test('degenerate sizes never rotate', () {
      expect(wallpaperNeedsRotation(Size.zero, portrait), isFalse);
      expect(wallpaperNeedsRotation(const Size(300, 100), Size.zero), isFalse);
    });

    test('the threshold moves the boundary', () {
      // The same 1.3:1 photo: worth a turn at the default 1.2, left alone once
      // the user asks for 1.5. This is the slider's whole effect.
      const photo = Size(1300, 1000);
      expect(wallpaperNeedsRotation(photo, portrait), isTrue);
      expect(wallpaperNeedsRotation(photo, portrait, threshold: 1.5), isFalse);
      expect(wallpaperNeedsRotation(photo, portrait, threshold: 1.05), isTrue);

      // A very wide photo survives even the strictest threshold.
      expect(wallpaperNeedsRotation(const Size(4000, 1000), portrait, threshold: 2), isTrue);
    });

    test('a threshold at or below one falls back to the default margin', () {
      // The slider cannot reach it, but a corrupt record must not turn every
      // nearly square photo.
      expect(wallpaperNeedsRotation(const Size(1100, 1000), portrait, threshold: 1), isFalse);
      expect(wallpaperNeedsRotation(const Size(1100, 1000), portrait, threshold: .5), isFalse);
    });
  });

  group('wallpaperRotationQuarterTurns', () {
    const portrait = Size(1080, 2400);
    const landscapePhoto = Size(3000, 2000);

    test('off never rotates', () {
      expect(wallpaperRotationQuarterTurns(photoSize: landscapePhoto, surfaceSize: portrait, rotation: WallpaperRotation.off, randomClockwise: true), 0);
    });

    test('the direction is the user choice', () {
      expect(wallpaperRotationQuarterTurns(photoSize: landscapePhoto, surfaceSize: portrait, rotation: WallpaperRotation.clockwise, randomClockwise: false), 1);
      expect(wallpaperRotationQuarterTurns(photoSize: landscapePhoto, surfaceSize: portrait, rotation: WallpaperRotation.counterClockwise, randomClockwise: true), 3);
    });

    test('random uses the drawn direction', () {
      expect(wallpaperRotationQuarterTurns(photoSize: landscapePhoto, surfaceSize: portrait, rotation: WallpaperRotation.random, randomClockwise: true), 1);
      expect(wallpaperRotationQuarterTurns(photoSize: landscapePhoto, surfaceSize: portrait, rotation: WallpaperRotation.random, randomClockwise: false), 3);
    });

    test('a matching orientation is never rotated, whatever the setting', () {
      // A portrait photo on a portrait screen: the direction setting is moot.
      for (final rotation in WallpaperRotation.values) {
        expect(wallpaperRotationQuarterTurns(photoSize: const Size(2000, 3000), surfaceSize: portrait, rotation: rotation, randomClockwise: true), 0);
      }
    });
  });

  group('wallpaperRandomClockwise', () {
    test('is stable for one slot seed and surface', () {
      expect(wallpaperRandomClockwise(1234, lock: false), wallpaperRandomClockwise(1234, lock: false));
      expect(wallpaperRandomClockwise(1234, lock: true), wallpaperRandomClockwise(1234, lock: true));
    });

    test('the two surfaces use different salts', () {
      // A seed can never be "wrong", but the lock must not simply mirror the
      // home draw: the salt has to change the hash.
      final home = [for (var seed = 0; seed < 16; seed++) wallpaperRandomClockwise(seed, lock: false)];
      final lock = [for (var seed = 0; seed < 16; seed++) wallpaperRandomClockwise(seed, lock: true)];
      expect(home, isNot(equals(lock)));
    });
  });

  group('GroupedFrameGeometry', () {
    test('the default is the identity', () {
      const geometry = GroupedFrameGeometry();
      expect(geometry.isIdentity, isTrue);
      expect(geometry.rotationDegrees, 0);
      expect(geometry.fit, WallpaperImageFit.fill);
    });

    test('JSON round-trips', () {
      const geometry = GroupedFrameGeometry(quarterTurns: 3, fit: WallpaperImageFit.stretch);
      final decoded = GroupedFrameGeometry.fromJsonMap(geometry.toJsonMap());
      expect(decoded, geometry);
      expect(decoded.rotationDegrees, 270);
      expect(GroupedFrameGeometry.fromJsonMap(null), const GroupedFrameGeometry());
    });

    test('the fit alone is not the identity', () {
      expect(const GroupedFrameGeometry(fit: WallpaperImageFit.fit).isIdentity, isFalse);
    });
  });
}
