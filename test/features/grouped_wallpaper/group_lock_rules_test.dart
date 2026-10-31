import 'package:aves/features/grouped_wallpaper/model/group_lock_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The group switch lock: group 0 and the locked group stay reachable, nothing
/// else does.
void main() {
  const lockedGroup = 'wallpaper.group.dcim';

  group('canSelectWallpaperGroup', () {
    test('unlocked groups may all be shown', () {
      expect(canSelectWallpaperGroup(locked: false, lockedGroupId: null, targetGroupId: null), isTrue);
      expect(canSelectWallpaperGroup(locked: false, lockedGroupId: null, targetGroupId: lockedGroup), isTrue);
      expect(canSelectWallpaperGroup(locked: false, lockedGroupId: null, targetGroupId: 'other'), isTrue);
    });

    test('locked keeps group 0 and the locked group', () {
      expect(canSelectWallpaperGroup(locked: true, lockedGroupId: lockedGroup, targetGroupId: null), isTrue);
      expect(canSelectWallpaperGroup(locked: true, lockedGroupId: lockedGroup, targetGroupId: lockedGroup), isTrue);
    });

    test('locked refuses every other group', () {
      expect(canSelectWallpaperGroup(locked: true, lockedGroupId: lockedGroup, targetGroupId: 'other'), isFalse);
    });

    test('a locked flag without a group still allows group 0', () {
      expect(canSelectWallpaperGroup(locked: true, lockedGroupId: null, targetGroupId: null), isTrue);
      expect(canSelectWallpaperGroup(locked: true, lockedGroupId: null, targetGroupId: lockedGroup), isFalse);
    });
  });

  group('canEditWallpaperGroupRange', () {
    test('both locks must be off', () {
      expect(canEditWallpaperGroupRange(rangeLocked: false, groupLocked: false), isTrue);
      expect(canEditWallpaperGroupRange(rangeLocked: true, groupLocked: false), isFalse);
      expect(canEditWallpaperGroupRange(rangeLocked: false, groupLocked: true), isFalse);
      expect(canEditWallpaperGroupRange(rangeLocked: true, groupLocked: true), isFalse);
    });
  });

  group('isWallpaperGroupTargetLocked', () {
    test('the gallery target is a separate lock', () {
      expect(isWallpaperGroupTargetLocked(isGallery: true, groupLocked: true), isFalse);
      expect(isWallpaperGroupTargetLocked(isGallery: false, groupLocked: true), isTrue);
      expect(isWallpaperGroupTargetLocked(isGallery: false, groupLocked: false), isFalse);
    });
  });
}
