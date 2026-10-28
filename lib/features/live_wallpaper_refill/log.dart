import 'package:aves/features/logging/log.dart';

/// Log channel owned by the shared live-wallpaper background pipeline.
const String liveWallpaperRefillLogKey = 'log.live_wallpaper_refill';

/// Channels this slice owns, opened in debug builds by `Log.init`.
const List<String> liveWallpaperRefillDebugLogKeys = [liveWallpaperRefillLogKey];

/// Shared logger for the headless refill entrypoint and its dispatch.
const AreaKeyLog liveWallpaperRefillLog = AreaKeyLog(liveWallpaperRefillLogKey);
