import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_browse_strips.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';

/// The strip that explains an empty media set must only appear when the gallery
/// range is the reason nothing is left: showing it for an empty group, an
/// already-ignored range or no wallpaper scope would teach the wrong cause.
void main() {
  // Any filter stands for a group here: the predicate only asks whether the
  // scope has one.
  final group = MimeFilter.image;

  bool shown({required bool isEmpty, VisibleRangeBrowsingOverlay? overlay, bool galleryRestricted = true}) => groupedWallpaperScopeHidesMediaSet(
        isEmpty: isEmpty,
        overlay: overlay,
        galleryRestricted: galleryRestricted,
      );

  test('an empty media set under an active scope is explained', () {
    expect(shown(isEmpty: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: group)), isTrue);
  });

  test('a non-empty media set needs no explanation', () {
    expect(shown(isEmpty: false, overlay: VisibleRangeBrowsingOverlay(groupFilter: group)), isFalse);
  });

  test('an unrestricted gallery range is not blamed', () {
    expect(shown(isEmpty: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: group), galleryRestricted: false), isFalse);
  });

  test('a suspended gallery range is already the way out', () {
    expect(shown(isEmpty: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: group, gallerySuspended: true)), isFalse);
  });

  test('group 0 has no scope of its own to hide', () {
    expect(shown(isEmpty: true, overlay: const VisibleRangeBrowsingOverlay()), isFalse);
    expect(shown(isEmpty: true), isFalse);
  });
}
