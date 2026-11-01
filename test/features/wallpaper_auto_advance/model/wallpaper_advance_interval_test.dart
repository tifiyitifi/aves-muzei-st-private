import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:flutter_test/flutter_test.dart';

/// The value object keeps arbitrary custom values, clamps only the bounds, and
/// treats `0` as off.
void main() {
  test('non-positive and unreadable values are off', () {
    for (final value in [null, 0, -1, -999, '900', 1.5]) {
      expect(WallpaperAdvanceInterval.fromSeconds(value), WallpaperAdvanceInterval.off, reason: '$value');
    }
  });

  test('values below the minimum clamp to three seconds', () {
    expect(WallpaperAdvanceInterval.fromSeconds(1), const WallpaperAdvanceInterval(3));
    expect(WallpaperAdvanceInterval.fromSeconds(2), const WallpaperAdvanceInterval(3));
    expect(WallpaperAdvanceInterval.fromSeconds(3), const WallpaperAdvanceInterval(3));
  });

  test('a custom value is preserved instead of falling back to off', () {
    // The enum reader used to return null for this, which turned a custom choice
    // into 「never」.
    expect(WallpaperAdvanceInterval.fromSeconds(2 * 60 * 60), const WallpaperAdvanceInterval(7200));
    expect(WallpaperAdvanceInterval.fromSeconds(900), const WallpaperAdvanceInterval(900));
  });

  test('values beyond thirty days clamp to the maximum', () {
    expect(WallpaperAdvanceInterval.fromSeconds(WallpaperAdvanceInterval.maxSeconds), const WallpaperAdvanceInterval(WallpaperAdvanceInterval.maxSeconds));
    expect(WallpaperAdvanceInterval.fromSeconds(WallpaperAdvanceInterval.maxSeconds + 1), const WallpaperAdvanceInterval(WallpaperAdvanceInterval.maxSeconds));
    expect(WallpaperAdvanceInterval.fromSeconds(1 << 40), const WallpaperAdvanceInterval(WallpaperAdvanceInterval.maxSeconds));
  });

  test('equality is by seconds', () {
    expect(const WallpaperAdvanceInterval(900), const WallpaperAdvanceInterval(900));
    expect(const WallpaperAdvanceInterval(900), isNot(const WallpaperAdvanceInterval(901)));
    expect(const WallpaperAdvanceInterval(900).hashCode, const WallpaperAdvanceInterval(900).hashCode);
  });
}
