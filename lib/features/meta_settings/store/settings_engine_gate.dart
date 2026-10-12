import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// Reads and writes the shared engine selector.
///
/// The selector lives in `SharedPreferences` (not in either settings store) so
/// it stays readable before a store is chosen and survives both engines'
/// `clear()`. The router hides it from the settings key space.
class SettingsEngineGate {
  static const String key = 'settings_engine';

  Future<SettingsEngineVersion> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SettingsEngineVersion.tryParse(prefs.getString(key)) ?? SettingsEngineVersion.defaultVersion;
    } catch (error, stack) {
      _log.w('failed to read engine gate, defaulting to ${SettingsEngineVersion.defaultVersion.name}', error, stack);
      return SettingsEngineVersion.defaultVersion;
    }
  }

  /// Persists [version]. Returns whether the write succeeded, so a caller can
  /// refuse to commit a switch whose selector would be lost on the next launch.
  Future<bool> write(SettingsEngineVersion version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(key, version.name);
      if (!success) {
        _log.e('failed to write engine gate=${version.name}');
      }
      return success;
    } catch (error, stack) {
      _log.e('failed to write engine gate=${version.name}', error, stack);
      return false;
    }
  }
}
