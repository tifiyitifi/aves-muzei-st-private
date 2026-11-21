import 'package:aves/features/logging/log.dart';

/// Log channel owned by the navigation-drawer pages slice.
const String navDrawerLogKey = 'log.nav_drawer';

/// Channels this feature owns, opened in debug builds by `Log.init`.
///
/// Declared here rather than in [LogKeys]: diagnostics for a fork feature stay
/// inside its own slice.
const List<String> navDrawerDebugLogKeys = [navDrawerLogKey];

/// Shared logger for the slice's defaults, migration and entry decisions.
const AreaKeyLog navDrawerLog = AreaKeyLog(navDrawerLogKey);
