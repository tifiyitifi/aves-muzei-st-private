import 'package:aves/features/logging/log.dart';

/// Log channel owned by session restore (never a shared catch-all).
///
/// A snapshot that fails to load is the answer to "why did the app not reopen
/// where I left it", so it needs its own channel instead of the media one.
const String sessionRestoreLogKey = 'log.session_restore';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> sessionRestoreDebugLogKeys = [sessionRestoreLogKey];

const AreaKeyLog sessionRestoreLog = AreaKeyLog(sessionRestoreLogKey);
