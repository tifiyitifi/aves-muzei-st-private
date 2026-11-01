import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_transition.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperTransition`: the durations the settings offer and the
/// tolerance of a value read back from a file another build wrote.
void main() {
  test('the default keeps a tap-feel duration', () {
    expect(GroupedWallpaperTransition.defaultTransition, GroupedWallpaperTransition.standard);
    expect(GroupedWallpaperTransition.defaultTransition.durationMs, 300);
    expect(GroupedWallpaperTransition.off.durationMs, 0);
  });

  test('an unknown name reads as the default', () {
    expect(GroupedWallpaperTransition.tryParse('standard'), GroupedWallpaperTransition.standard);
    expect(GroupedWallpaperTransition.tryParse('off'), GroupedWallpaperTransition.off);
    expect(GroupedWallpaperTransition.tryParse(null), GroupedWallpaperTransition.defaultTransition);
    expect(GroupedWallpaperTransition.tryParse('fast'), GroupedWallpaperTransition.defaultTransition);
  });

  test('a duration outside the switches keeps the closest one', () {
    expect(GroupedWallpaperTransition.fromDuration(0), GroupedWallpaperTransition.off);
    expect(GroupedWallpaperTransition.fromDuration(120), GroupedWallpaperTransition.short);
    expect(GroupedWallpaperTransition.fromDuration(420), GroupedWallpaperTransition.long);
    expect(GroupedWallpaperTransition.fromDuration(10_000), GroupedWallpaperTransition.long);
    expect(GroupedWallpaperTransition.fromDuration(null), GroupedWallpaperTransition.defaultTransition);
    expect(GroupedWallpaperTransition.fromDuration('fast'), GroupedWallpaperTransition.defaultTransition);
  });
}
