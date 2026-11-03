import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_control_pad_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the view page's floating control pad may rest: the normalized place,
/// the clamp that keeps it on screen and the centered default anchor.
void main() {
  const viewport = Size(400, 800);
  const extent = Size(160, 144);
  const free = Size(
    400 - 2 * groupedWallpaperControlPadMargin - 160,
    800 - 2 * groupedWallpaperControlPadMargin - 144,
  );

  test('the extent is the grid plus the handle', () {
    expect(groupedWallpaperControlPadExtentFor(columns: 3, rows: 3), const Size(16 + 3 * 48, 3 * 48));
    expect(groupedWallpaperControlPadExtentFor(columns: 2, rows: 1), const Size(16 + 2 * 48, 48));
  });

  test('the default anchor puts the pad top-left at the screen center', () {
    final position = groupedWallpaperControlPadCenteredDefault(viewportSize: viewport, safeInsets: EdgeInsets.zero, extent: extent);
    final topLeft = groupedWallpaperControlPadTopLeft(position: position, viewportSize: viewport, safeInsets: EdgeInsets.zero, extent: extent);
    expect(topLeft.dx, closeTo(viewport.width / 2, .001));
    expect(topLeft.dy, closeTo(viewport.height / 2, .001));
  });

  test('the centered anchor is clamped inside a small safe area', () {
    const insets = EdgeInsets.fromLTRB(10, 20, 10, 20);
    final position = groupedWallpaperControlPadCenteredDefault(viewportSize: viewport, safeInsets: insets, extent: extent);
    final topLeft = groupedWallpaperControlPadTopLeft(position: position, viewportSize: viewport, safeInsets: insets, extent: extent);
    expect(topLeft.dx, greaterThanOrEqualTo(insets.left + groupedWallpaperControlPadMargin));
    expect(topLeft.dy, greaterThanOrEqualTo(insets.top + groupedWallpaperControlPadMargin));
  });

  test('the place is a fraction of the free space, not of the viewport', () {
    final topLeft = groupedWallpaperControlPadTopLeft(
      position: const GroupedWallpaperControlPadPosition(.5, .5),
      viewportSize: viewport,
      safeInsets: EdgeInsets.zero,
      extent: extent,
    );
    expect(topLeft.dx, closeTo(groupedWallpaperControlPadMargin + free.width / 2, .001));
    expect(topLeft.dy, closeTo(groupedWallpaperControlPadMargin + free.height / 2, .001));
  });

  test('safe-area insets move both the usable rect and the pad', () {
    const insets = EdgeInsets.fromLTRB(10, 40, 10, 30);
    final topLeft = groupedWallpaperControlPadTopLeft(
      position: const GroupedWallpaperControlPadPosition(0, 0),
      viewportSize: viewport,
      safeInsets: insets,
      extent: extent,
    );
    expect(topLeft.dx, 10 + groupedWallpaperControlPadMargin);
    expect(topLeft.dy, 40 + groupedWallpaperControlPadMargin);
  });

  test('a rotation keeps the fractional place inside the new screen', () {
    const landscape = Size(800, 400);
    final topLeft = groupedWallpaperControlPadTopLeft(
      position: const GroupedWallpaperControlPadPosition(1, 1),
      viewportSize: landscape,
      safeInsets: EdgeInsets.zero,
      extent: extent,
    );
    expect(topLeft.dx, 800 - groupedWallpaperControlPadMargin - extent.width);
    expect(topLeft.dy, 400 - groupedWallpaperControlPadMargin - extent.height);
  });

  test('a drag past the edge is clamped back', () {
    expect(
      clampGroupedWallpaperControlPadPosition(
        position: const GroupedWallpaperControlPadPosition(4, -2),
        viewportSize: viewport,
        safeInsets: EdgeInsets.zero,
        extent: extent,
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
      extent: extent,
    );
    expect(position, const GroupedWallpaperControlPadPosition(0, 0));
    expect(
      groupedWallpaperControlPadTopLeft(position: position, viewportSize: tiny, safeInsets: EdgeInsets.zero, extent: extent),
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
