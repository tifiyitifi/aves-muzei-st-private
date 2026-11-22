import 'dart:math';

/// The bounded range of a displayed order the viewer receives, or null when
/// [position] falls outside it.
///
/// The viewer gets a window instead of the whole order: a selection of 30,000
/// rows would materialize exactly the library the index exists to keep compact,
/// while swiping stays useful across a few hundred neighbours. The returned
/// range is half-open `[from, to)` and always contains [position].
({int from, int to})? viewerWindow({required int length, required int position, int radius = 250}) {
  if (position < 0 || position >= length) return null;
  final from = max(0, position - radius);
  final to = min(length, position + radius + 1);
  return (from: from, to: to);
}
