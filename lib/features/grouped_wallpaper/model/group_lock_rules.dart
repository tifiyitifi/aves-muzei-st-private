/// Decisions the group switch lock makes, kept free of widgets so they can be
/// tested and so every surface (page, history, pin sheet) agrees.
///
/// The lock freezes one group: the user may still look at group 0 ("every
/// image") and at the locked group itself, but not at another group, not edit
/// the locked group's rules, and not pin content into any group. Switching away
/// would be an indirect way to see what the lock hides, which is why the
/// notification's group buttons and "set as wallpaper" are frozen too.
library;

/// Whether [targetGroupId] (null is group 0) may be shown while the lock is on.
///
/// Group 0 stays available so the user can still browse the whole library; it
/// also clears the group browsing scope, which is the documented way out.
bool canSelectWallpaperGroup({
  required bool locked,
  required String? lockedGroupId,
  required String? targetGroupId,
}) {
  if (!locked) return true;
  if (targetGroupId == null) return true;
  return targetGroupId == lockedGroupId;
}

/// Whether the selected group's range may be edited.
///
/// Both the range's own lock and the group switch lock freeze edits; either one
/// is enough to refuse.
bool canEditWallpaperGroupRange({required bool rangeLocked, required bool groupLocked}) => !rangeLocked && !groupLocked;

/// Whether a pin-sheet target belongs to a group the lock freezes.
///
/// The gallery's own range is a separate lock, so it is never frozen here.
bool isWallpaperGroupTargetLocked({required bool isGallery, required bool groupLocked}) => groupLocked && !isGallery;
