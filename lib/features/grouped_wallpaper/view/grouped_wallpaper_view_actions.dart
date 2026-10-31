import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';

/// Whether the "previous photo" control would do anything.
///
/// The engine walks the state's rewind stack, so this mirrors it exactly: no
/// photo on screen, a turned-off or unavailable wallpaper, recording off, or the
/// cursor already at the oldest record all grey the control instead of offering
/// a tap that does nothing.
bool groupedWallpaperCanGoPrevious(GroupedWallpaperState state) => state.canGoPrevious;

/// Whether the "next photo" control would change the frame.
///
/// A group with a single photo would re-bake the same frame, so the control is
/// greyed out instead of pretending to advance.
bool groupedWallpaperCanGoNext(GroupedWallpaperState state) => state.hasPhoto && state.count > 1;
