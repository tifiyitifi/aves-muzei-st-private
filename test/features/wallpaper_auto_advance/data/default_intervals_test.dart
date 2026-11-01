import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled document is tolerant at runtime and sane as shipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('malformed documents fall back to off only', () {
    for (final source in ['', '{', '[]', 'null', '{"intervals":42}']) {
      final defaults = parseWallpaperIntervalDefaults(source);
      expect(defaults.defaultInterval, WallpaperAdvanceInterval.off, reason: source);
      expect(defaults.intervals, [WallpaperAdvanceInterval.off], reason: source);
    }
  });

  test('parses, deduplicates, sorts and keeps off plus the reset target', () {
    final defaults = parseWallpaperIntervalDefaults('''
      {
        "version": 7,
        "defaultSeconds": 1800,
        "intervals": [3600, "bad", 900, 900, -5, 1, 2, 0, 259200, 2592001]
      }
    ''');
    expect(defaults.version, 7);
    expect(defaults.defaultInterval, const WallpaperAdvanceInterval(1800));
    expect(defaults.intervals, const [
      WallpaperAdvanceInterval.off,
      WallpaperAdvanceInterval(900),
      WallpaperAdvanceInterval(1800),
      WallpaperAdvanceInterval(3600),
      WallpaperAdvanceInterval(259200),
    ]);
  });

  test('a reset target missing from the list is added', () {
    final defaults = parseWallpaperIntervalDefaults('{"defaultSeconds": 7200, "intervals": [0, 900]}');
    expect(defaults.intervals, contains(const WallpaperAdvanceInterval(7200)));
  });

  test('the shipped asset is a valid, ordered option list', () async {
    final defaults = await loadWallpaperIntervalDefaults();
    expect(defaults.version, 1);
    expect(defaults.defaultInterval, WallpaperAdvanceInterval.off);
    expect(defaults.intervals, isNotEmpty);
    expect(defaults.intervals.first, WallpaperAdvanceInterval.off);
    expect(defaults.intervals.toSet(), hasLength(defaults.intervals.length));
    for (var i = 1; i < defaults.intervals.length; i++) {
      expect(defaults.intervals[i].seconds, greaterThan(defaults.intervals[i - 1].seconds));
    }
    for (final interval in defaults.intervals) {
      expect(interval.seconds, inInclusiveRange(0, WallpaperAdvanceInterval.maxSeconds));
      expect(interval.isWithinBounds, isTrue);
    }
  });
}
