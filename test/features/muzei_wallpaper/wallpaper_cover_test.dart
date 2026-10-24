import 'package:aves/features/muzei_wallpaper/model/wallpaper_cover.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('coverSizeFor', () {
    test('a very tall artwork overflows vertically on a long screen', () {
      // 1:3 artwork in a 1080x2400 window: filling the width leaves extra height.
      final size = coverSizeFor(const Size(1080, 2400), 1 / 3);
      expect(size.width, 1080);
      expect(size.height, closeTo(1080 * 3, 1e-9));
      expect(size.height, greaterThan(2400));
    });

    test('a wider artwork overflows horizontally', () {
      // 3:4 artwork: filling the height leaves extra width.
      final size = coverSizeFor(const Size(1080, 2400), 3 / 4);
      expect(size.height, 2400);
      expect(size.width, closeTo(2400 * 3 / 4, 1e-9));
      expect(size.width, greaterThan(1080));
    });

    test('a matching aspect ratio fills the viewport exactly', () {
      final size = coverSizeFor(const Size(1080, 2400), 1080 / 2400);
      expect(size.width, closeTo(1080, 1e-9));
      expect(size.height, closeTo(2400, 1e-9));
    });

    test('an unknown aspect ratio falls back to the viewport', () {
      expect(coverSizeFor(const Size(1080, 2400), null), const Size(1080, 2400));
      expect(coverSizeFor(const Size(1080, 2400), 0), const Size(1080, 2400));
      expect(coverSizeFor(const Size(1080, 2400), double.nan), const Size(1080, 2400));
      expect(coverSizeFor(Size.zero, 1.5), Size.zero);
    });
  });

  group('centeredCoverMatrix', () {
    test('shifts the child by half its overflow on each axis', () {
      final matrix = centeredCoverMatrix(const Size(1200, 2400), const Size(1080, 2400));
      expect(matrix.getTranslation().x, -60);
      expect(matrix.getTranslation().y, 0);
    });

    test('is the identity when the child matches the viewport', () {
      final matrix = centeredCoverMatrix(const Size(1080, 2400), const Size(1080, 2400));
      expect(matrix, Matrix4.identity());
    });
  });
}
