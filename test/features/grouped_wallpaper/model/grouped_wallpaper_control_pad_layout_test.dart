import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_control_pad_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the view page's floating control pad may rest: the normalized place,
/// the clamp that keeps it on screen and the tolerance of a stored value.
void main() {
  const viewport = Size(400, 800);
  const free = Size(
    400 - 2 * groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent,
    800 - 2 * groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent,
  );

  test('the default anchor sits on the left, a little below the middle', () {
    const position = GroupedWallpaperControlPadPosition.defaultPosition;
    expect(position.x, 0);
    expect(position.y, greaterThan(.5));
    expect(position.y, lessThan(1));
  });

  test('the place is a fraction of the free space, not of the viewport', () {
    final topLeft = groupedWallpaperControlPadTopLeft(
      position: const GroupedWallpaperControlPadPosition(.5, .5),
      viewportSize: viewport,
      safeInsets: EdgeInsets.zero,
    );
    expect(topLeft.dx, closeTo(groupedWallpaperControlPadMargin + free.width / 2, .001));
    expect(topLeft.dy, closeTo(groupedWallpaperControlPadMargin + free.height / 2, .001));
  });

  test('safe-area insets move both the usable rect and the pad', () {
    const insets = EdgeInsets.fromLTRB(10, 40, 10, 30);
    final topLeft = groupedWallpaperControlPadTopLeft(
      position: GroupedWallpaperControlPadPosition.defaultPosition,
      viewportSize: viewport,
      safeInsets: insets,
    );
    expect(topLeft.dx, 10 + groupedWallpaperControlPadMargin);
    expect(topLeft.dy, greaterThan(40 + groupedWallpaperControlPadMargin));
  });

  test('a rotation keeps the fractional place inside the new screen', () {
    const landscape = Size(800, 400);
    final topLeft = groupedWallpaperControlPadTopLeft(
      position: const GroupedWallpaperControlPadPosition(1, 1),
      viewportSize: landscape,
      safeInsets: EdgeInsets.zero,
    );
    expect(topLeft.dx, 800 - groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent);
    expect(topLeft.dy, 400 - groupedWallpaperControlPadMargin - groupedWallpaperControlPadExtent);
  });

  test('a drag past the edge is clamped back', () {
    expect(
      clampGroupedWallpaperControlPadPosition(
        position: const GroupedWallpaperControlPadPosition(4, -2),
        viewportSize: viewport,
        safeInsets: EdgeInsets.zero,
      ),
      const GroupedWallpaperControlPadPosition(1, 0),
    );
  });

  test('a viewport smaller than the pad pins it to the usable origin', () {
    const tiny = Size(120, 120);
    final position = groupedWallpaperControlPadPositionFrom(
      topLeft: const Offset(300, 300),
      viewportSize: tiny,
      safeInsets: EdgeInsets.zero,
    );
    expect(position, const GroupedWallpaperControlPadPosition(0, 0));
    expect(
      groupedWallpaperControlPadTopLeft(position: position, viewportSize: tiny, safeInsets: EdgeInsets.zero),
      const Offset(groupedWallpaperControlPadMargin, groupedWallpaperControlPadMargin),
    );
  });

  test('a stored value round-trips and is clamped on read', () {
    const position = GroupedWallpaperControlPadPosition(.25, .75);
    expect(GroupedWallpaperControlPadPosition.tryParse(position.encode()), position);
    expect(GroupedWallpaperControlPadPosition.tryParse('2,-1'), const GroupedWallpaperControlPadPosition(1, 0));
    expect(GroupedWallpaperControlPadPosition.tryParse('1'), isNull);
    expect(GroupedWallpaperControlPadPosition.tryParse('nonsense'), isNull);
    expect(GroupedWallpaperControlPadPosition.tryParse('NaN,0.5'), isNull);
    expect(GroupedWallpaperControlPadPosition.tryParse(null), isNull);
  });
}
