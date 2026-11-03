import 'package:flutter/painting.dart';

import 'package:equatable/equatable.dart';

/// One cell of the view page's floating control pad, in logical pixels.
///
/// The pad is a 3x3 box whose three rows carry 3, 2 and 1 controls and are
/// left-aligned, which is what makes the silhouette read as a top-left bracket.
/// The size is a rule rather than a measured value, so clamping a drag needs no
/// layout pass and moving the pad never lays the photo out again.
const groupedWallpaperControlPadCell = 48.0;

/// The pad's box: three cells either way.
const groupedWallpaperControlPadExtent = 3 * groupedWallpaperControlPadCell;

/// Space the pad keeps from the safe area's edges, clear of the gesture bar and
/// the screen border.
const groupedWallpaperControlPadMargin = 12.0;

/// Where the pad rests, as a fraction of the free space inside the safe area.
///
/// Fractions rather than pixels: a rotation or a window resize keeps the pad
/// where the thumb put it instead of pinning it to an edge. A stored value is
/// clamped when parsed, so a hand-edited row cannot push the pad off screen.
class GroupedWallpaperControlPadPosition extends Equatable {
  final double x;
  final double y;

  const new(this.x, this.y);

  /// Left edge, a little below the middle: reachable by a thumb and clear of
  /// the info panel on a phone held in one hand.
  static const defaultPosition = GroupedWallpaperControlPadPosition(0, .55);

  /// Reads a value written by [encode], clamped to the valid range.
  ///
  /// Anything else is null, and the caller falls back to the default anchor.
  static GroupedWallpaperControlPadPosition? tryParse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return GroupedWallpaperControlPadPosition(x.clamp(0, 1).toDouble(), y.clamp(0, 1).toDouble());
  }

  /// The stored form: `x,y`, lossless so a round trip keeps the exact drag.
  String encode() => '$x,$y';

  @override
  List<Object?> get props => [x, y];
}

/// The area the pad may occupy: the safe area, inset by [groupedWallpaperControlPadMargin].
Rect groupedWallpaperControlPadUsableRect({required Size viewportSize, required EdgeInsets safeInsets}) {
  final left = safeInsets.left + groupedWallpaperControlPadMargin;
  final top = safeInsets.top + groupedWallpaperControlPadMargin;
  // A viewport smaller than the insets plus the pad still yields a sane (empty)
  // rect instead of an inverted one, so the clamp below can only ever pin the
  // pad to the top-left corner.
  final right = left > viewportSize.width - safeInsets.right - groupedWallpaperControlPadMargin ? left : viewportSize.width - safeInsets.right - groupedWallpaperControlPadMargin;
  final bottom = top > viewportSize.height - safeInsets.bottom - groupedWallpaperControlPadMargin ? top : viewportSize.height - safeInsets.bottom - groupedWallpaperControlPadMargin;
  return Rect.fromLTRB(left, top, right, bottom);
}

/// The space a top-left corner may move in, i.e. the usable rect minus the pad.
Size groupedWallpaperControlPadFreeSpace(Rect usableRect) => Size(
  (usableRect.width - groupedWallpaperControlPadExtent).clamp(0, double.infinity).toDouble(),
  (usableRect.height - groupedWallpaperControlPadExtent).clamp(0, double.infinity).toDouble(),
);

/// The pad's top-left corner for [position].
Offset groupedWallpaperControlPadTopLeft({
  required GroupedWallpaperControlPadPosition position,
  required Size viewportSize,
  required EdgeInsets safeInsets,
}) {
  final usable = groupedWallpaperControlPadUsableRect(viewportSize: viewportSize, safeInsets: safeInsets);
  final free = groupedWallpaperControlPadFreeSpace(usable);
  return Offset(usable.left + position.x * free.width, usable.top + position.y * free.height);
}

/// The normalized position of a pad whose top-left corner is [topLeft].
GroupedWallpaperControlPadPosition groupedWallpaperControlPadPositionFrom({
  required Offset topLeft,
  required Size viewportSize,
  required EdgeInsets safeInsets,
}) {
  final usable = groupedWallpaperControlPadUsableRect(viewportSize: viewportSize, safeInsets: safeInsets);
  final free = groupedWallpaperControlPadFreeSpace(usable);
  return GroupedWallpaperControlPadPosition(
    free.width <= 0 ? 0 : ((topLeft.dx - usable.left) / free.width).clamp(0, 1).toDouble(),
    free.height <= 0 ? 0 : ((topLeft.dy - usable.top) / free.height).clamp(0, 1).toDouble(),
  );
}

/// [position] moved back inside the screen, for a drag that left it.
GroupedWallpaperControlPadPosition clampGroupedWallpaperControlPadPosition({
  required GroupedWallpaperControlPadPosition position,
  required Size viewportSize,
  required EdgeInsets safeInsets,
}) => groupedWallpaperControlPadPositionFrom(
  topLeft: groupedWallpaperControlPadTopLeft(position: position, viewportSize: viewportSize, safeInsets: safeInsets),
  viewportSize: viewportSize,
  safeInsets: safeInsets,
);
