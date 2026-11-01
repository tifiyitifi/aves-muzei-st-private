import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_parts.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four-box editor and [WallpaperAdvanceInterval] share one set of bounds;
/// the ordering of the boxes is days, hours, minutes, seconds.
void main() {
  test('an existing interval decomposes into its boxes', () {
    expect(WallpaperIntervalParts.fromSeconds(10 * 60), const WallpaperIntervalParts(minutes: 10));
    expect(WallpaperIntervalParts.fromSeconds(90), const WallpaperIntervalParts(minutes: 1, seconds: 30));
    expect(WallpaperIntervalParts.fromSeconds(2 * 60 * 60), const WallpaperIntervalParts(hours: 2));
    expect(
      WallpaperIntervalParts.fromSeconds(Duration.secondsPerDay + 2 * Duration.secondsPerHour + 3 * Duration.secondsPerMinute + 4),
      const WallpaperIntervalParts(days: 1, hours: 2, minutes: 3, seconds: 4),
    );
    expect(WallpaperIntervalParts.fromSeconds(WallpaperAdvanceInterval.maxSeconds), const WallpaperIntervalParts(days: 30));
  });

  test('off decomposes to all-zero boxes, not to the default', () {
    expect(WallpaperIntervalParts.fromSeconds(0), const WallpaperIntervalParts());
    expect(WallpaperIntervalParts.fromSeconds(-5), const WallpaperIntervalParts());
  });

  test('the boxes sum back to seconds', () {
    expect(const WallpaperIntervalParts(minutes: 10).totalSeconds, 600);
    expect(const WallpaperIntervalParts(days: 1, hours: 2, minutes: 3, seconds: 4).totalSeconds, 93784);
    expect(const WallpaperIntervalParts().totalSeconds, 0);
  });

  test('the editor default is ten minutes', () {
    expect(WallpaperIntervalParts.defaultTenMinutes.totalSeconds, 600);
    expect(WallpaperIntervalParts.defaultTenMinutes, const WallpaperIntervalParts(minutes: 10));
  });

  test('the bounds match the interval value object', () {
    bool valid(int days, int hours, int minutes, int seconds) =>
        WallpaperIntervalParts(days: days, hours: hours, minutes: minutes, seconds: seconds).isValid;

    expect(valid(0, 0, 0, WallpaperAdvanceInterval.minSeconds), isTrue);
    expect(valid(0, 0, 0, WallpaperAdvanceInterval.minSeconds - 1), isFalse);
    expect(valid(0, 0, 0, 0), isFalse, reason: 'Off is a built-in, not an editor value');
    expect(valid(30, 0, 0, 0), isTrue);
    // 30 days + 1 second is one second past the scheduler's maximum.
    expect(valid(30, 0, 0, 1), isFalse);
    expect(valid(1000, 0, 0, 0), isFalse);
  });

  test('each box is capped at one thousand', () {
    expect(const WallpaperIntervalParts(days: WallpaperIntervalParts.maxFieldValue).isWithinFieldBounds, isTrue);
    expect(const WallpaperIntervalParts(days: WallpaperIntervalParts.maxFieldValue + 1).isWithinFieldBounds, isFalse);
    expect(const WallpaperIntervalParts(minutes: -1).isWithinFieldBounds, isFalse);
    expect(const WallpaperIntervalParts(hours: 999, minutes: 59).isValid, isFalse, reason: '999 hours is past 30 days');
  });

  test('equality is by boxes', () {
    expect(const WallpaperIntervalParts(minutes: 10), const WallpaperIntervalParts(minutes: 10));
    expect(const WallpaperIntervalParts(minutes: 10), isNot(const WallpaperIntervalParts(seconds: 600)));
  });
}
