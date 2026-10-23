import 'package:aves/features/logging/log.dart';

/// Log channel owned by the live-wallpaper feature.
const String liveWallpaperLogKey = 'log.live_wallpaper';

/// Channels this feature owns, opened in debug builds by `Log.init`.
///
/// Declared here rather than in [LogKeys]: diagnostics for a fork feature stay
/// inside its own slice.
const List<String> liveWallpaperDebugLogKeys = [liveWallpaperLogKey];

/// Shared logger for the feature's models, services and background entrypoint.
const AreaKeyLog wallpaperLog = AreaKeyLog(liveWallpaperLogKey);
