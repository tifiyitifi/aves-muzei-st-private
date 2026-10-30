import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';

/// Whether the "previous photo" control would do anything.
///
/// Mirrors the engine's `_runPrevious`: recording off (`historyLimit <= 0`), no
/// photo on screen, or no other entry of the same group in the history means
/// there is nothing to step back to. The old entries without a group id predate
/// the field and are accepted, exactly like the engine does.
bool groupedWallpaperCanGoPrevious(GroupedWallpaperState state) {
  if (!state.hasPhoto || state.historyLimit <= 0) return false;
  return state.recent.any((entry) => (entry.groupId.isEmpty || entry.groupId == state.groupId) && entry.entryId != state.entryId);
}

/// Whether the "next photo" control would change the frame.
///
/// A group with a single photo would re-bake the same frame, so the control is
/// greyed out instead of pretending to advance.
bool groupedWallpaperCanGoNext(GroupedWallpaperState state) => state.hasPhoto && state.count > 1;
