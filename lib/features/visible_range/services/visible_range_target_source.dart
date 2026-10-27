import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';

/// Ranges owned by another surface, registered with the visible-range feature.
///
/// The gallery owns exactly one range; wallpaper groups own one range each. The
/// pin sheet and the write-back list must reach both without the visible-range
/// feature importing the grouped-wallpaper one, so the composition root sets a
/// source on `VisibleRangeController`.
abstract interface class VisibleRangeTargetSource {
  /// Extra pin targets in display order (wallpaper groups `1..n`), each already
  /// flagged when its range refuses edits.
  Future<List<VisibleRangePinTarget>> loadPinTargets();

  /// The range with [rangeId], or null when it is unknown.
  Future<VisibleRange?> loadRange(String rangeId);

  /// Persists a range owned by this source.
  Future<void> saveRange(VisibleRange range);
}
