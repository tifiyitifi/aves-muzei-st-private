import 'package:aves/features/logging/log.dart';

/// Log channel owned by the grouped-wallpaper feature.
const String groupedWallpaperLogKey = 'log.grouped_wallpaper';

/// Channels this feature owns, opened in debug builds by `Log.init`.
///
/// Declared here rather than in [LogKeys]: diagnostics for a fork feature stay
/// inside its own slice.
const List<String> groupedWallpaperDebugLogKeys = [groupedWallpaperLogKey];

/// Shared logger for the feature's models, services and page.
const AreaKeyLog groupedWallpaperLog = AreaKeyLog(groupedWallpaperLogKey);
