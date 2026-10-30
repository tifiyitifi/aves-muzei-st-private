import 'package:aves/features/logging/log.dart';

/// Log channel owned by the wallpaper-lock feature.
const String wallpaperLockLogKey = 'log.wallpaper_lock';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> wallpaperLockDebugLogKeys = [wallpaperLockLogKey];

const AreaKeyLog wallpaperLockLog = AreaKeyLog(wallpaperLockLogKey);
