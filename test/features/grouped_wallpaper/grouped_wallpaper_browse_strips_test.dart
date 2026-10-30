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
  final groupFilter = MimeFilter.image;

  bool shown({required bool isEmpty, VisibleRangeBrowsingOverlay? overlay, bool galleryRestricted = true}) => groupedWallpaperScopeHidesMediaSet(
        isEmpty: isEmpty,
        overlay: overlay,
        galleryRestricted: galleryRestricted,
      );

  test('an empty media set under an active scope is explained', () {
    expect(shown(isEmpty: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter)), isTrue);
  });

  test('a non-empty media set needs no explanation', () {
    expect(shown(isEmpty: false, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter)), isFalse);
  });

  test('an unrestricted gallery range is not blamed', () {
    expect(shown(isEmpty: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter), galleryRestricted: false), isFalse);
  });

  test('a suspended gallery range is already the way out', () {
    expect(shown(isEmpty: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter, gallerySuspended: true)), isFalse);
  });

  test('group 0 has no scope of its own to hide', () {
    expect(shown(isEmpty: true, overlay: const VisibleRangeBrowsingOverlay()), isFalse);
    expect(shown(isEmpty: true), isFalse);
  });

  group('strip order', () {
    List<GroupedWallpaperBrowseStrip> strips({
      bool restoreOffered = false,
      bool gallerySuspended = false,
      bool awaitingFirstWindow = false,
      bool isEmpty = true,
      VisibleRangeBrowsingOverlay? overlay,
      bool galleryRestricted = true,
    }) => groupedWallpaperBrowseStrips(
      restoreOffered: restoreOffered,
      gallerySuspended: gallerySuspended,
      awaitingFirstWindow: awaitingFirstWindow,
      isEmpty: isEmpty,
      overlay: overlay,
      galleryRestricted: galleryRestricted,
    );

    test('a suspended range is announced even when the media set is not empty', () {
      // Without the reminder the only way back is a menu the user may not find.
      expect(strips(isEmpty: false, gallerySuspended: true), [GroupedWallpaperBrowseStrip.suspended]);
    });

    test('a suspended range replaces the empty-set explanation', () {
      expect(strips(gallerySuspended: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter)), [GroupedWallpaperBrowseStrip.suspended]);
    });

    test('the wallpaper notice comes first and the range reminders follow', () {
      expect(strips(restoreOffered: true, gallerySuspended: true), [GroupedWallpaperBrowseStrip.restore, GroupedWallpaperBrowseStrip.suspended]);
    });

    test('nothing is shown when the scope explains nothing and the range is intact', () {
      expect(strips(isEmpty: false, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter)), isEmpty);
      expect(strips(awaitingFirstWindow: true, overlay: VisibleRangeBrowsingOverlay(groupFilter: groupFilter)), isEmpty);
    });
  });
}
