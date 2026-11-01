import 'package:aves/features/logging/log.dart';

/// Log channel owned by the wallpaper interval-option slice.
const String wallpaperAutoAdvanceLogKey = 'log.wallpaper_auto_advance';

/// Channels this feature owns, opened in debug builds by `Log.init`.
///
/// Declared here rather than in [LogKeys]: diagnostics for a fork feature stay
/// inside its own slice.
const List<String> wallpaperAutoAdvanceDebugLogKeys = [wallpaperAutoAdvanceLogKey];

/// Shared logger for the catalog, its store and its management surfaces.
const AreaKeyLog wallpaperAutoAdvanceLog = AreaKeyLog(wallpaperAutoAdvanceLogKey);
