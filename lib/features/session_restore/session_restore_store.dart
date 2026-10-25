import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/session_restore/session_restore_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = AreaKeyLog(LogKeys.media);

/// Persists the one snapshot the next cold start may reopen.
class SessionRestoreStore {
  static const String snapshotKey = 'session_restore.snapshot';

  final Future<SharedPreferences> Function() _prefsProvider;

  new({Future<SharedPreferences> Function()? prefsProvider}) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  Future<SessionRestoreSnapshot?> load() async {
    try {
      final prefs = await _prefsProvider();
      return SessionRestoreSnapshot.tryFromJsonString(prefs.getString(snapshotKey));
    } catch (error, stack) {
      _log.w('failed to load the session restore snapshot', error, stack);
      return null;
    }
  }

  Future<void> save(SessionRestoreSnapshot snapshot) async {
    if (!snapshot.isValid) return;
    try {
      final prefs = await _prefsProvider();
      await prefs.setString(snapshotKey, snapshot.toJsonString());
    } catch (error, stack) {
      _log.w('failed to save the session restore snapshot', error, stack);
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await _prefsProvider();
      await prefs.remove(snapshotKey);
    } catch (error, stack) {
      _log.w('failed to clear the session restore snapshot', error, stack);
    }
  }
}

final SessionRestoreStore sessionRestoreStore = SessionRestoreStore();
