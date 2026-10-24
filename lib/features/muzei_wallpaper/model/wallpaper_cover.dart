import 'package:flutter/widgets.dart';

/// Lays an artwork out so it covers [viewport] at 1x, exactly like
/// `BoxFit.cover`.
///
/// The wallpaper crops the artwork to the screen. Laying the page's artwork out
/// at this size keeps the cropped parts inside the widget, so dragging can pan
/// to them even at 1x, which is what Muzei's normalized artwork viewport does.
/// Falls back to [viewport] when the artwork's aspect ratio is unknown (older
/// state files), which keeps the page usable, just without spare pan range.
Size coverSizeFor(Size viewport, double? aspectRatio) {
  if (aspectRatio == null || aspectRatio <= 0 || aspectRatio.isNaN || aspectRatio.isInfinite) return viewport;
  if (viewport.width <= 0 || viewport.height <= 0) return viewport;
  if (viewport.width / viewport.height > aspectRatio) {
    // The viewport is wider than the artwork: covering it overflows vertically.
    return Size(viewport.width, viewport.width / aspectRatio);
  }
  return Size(viewport.height * aspectRatio, viewport.height);
}

/// The transform that centers [childSize] inside [viewportSize].
///
/// `InteractiveViewer` lays an unconstrained child out at the parent's top-left,
/// so the initial pan must move it back by half the overflow on each axis.
Matrix4 centeredCoverMatrix(Size childSize, Size viewportSize) {
  return Matrix4.translationValues(
    (viewportSize.width - childSize.width) / 2,
    (viewportSize.height - childSize.height) / 2,
    0,
  );
}
