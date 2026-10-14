import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/store/meta_settings_seeder.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/model/settings/store_shared_pref.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// The single `SettingsStore`, delegating to whichever engine [SettingsEngineGate]
/// selects.
///
/// The rest of the app keeps reading `settings.*` through this seam, so the
/// engine swap is invisible to callers. The gate key is hidden from [getKeys]
/// (and preserved across [clear]) so settings export/import/reset never touch it.
class SettingsStoreRouter implements SettingsStore {
  new({
    SharedPrefSettingsStore? legacy,
    MetaSettingsStore? meta,
    SettingsEngineGate? gate,
  })  : _legacy = legacy ?? SharedPrefSettingsStore(),
        _meta = meta ?? MetaSettingsStore(),
        _gate = gate ?? SettingsEngineGate();

  final SharedPrefSettingsStore _legacy;
  final MetaSettingsStore _meta;
  final SettingsEngineGate _gate;

  SettingsEngineVersion _version = SettingsEngineVersion.defaultVersion;

  SettingsEngineVersion get version => _version;

  bool get isMeta => _version == SettingsEngineVersion.v2;

  SharedPrefSettingsStore get legacyStore => _legacy;

  MetaSettingsStore get metaStore => _meta;

  SettingsStore get _active => isMeta ? _meta : _legacy;

  /// The engine selector is not a setting: [remove] ignores it, [getKeys] hides
  /// it and [clear] re-asserts it, so writes must be ignored too. Otherwise a
  /// stray `SettingsAccess.set(gate)` would pollute the authoritative store —
  /// and, while the legacy engine is active, silently overwrite the real gate
  /// (it shares the same `SharedPreferences` file).
  bool _ignoresGateWrite(String key) {
    if (key != SettingsEngineGate.key) return false;
    _log.w('ignored a write to the settings engine gate key');
    return true;
  }

  /// The gate is not part of the settings key space: reads must hide it too.
  /// While the legacy engine is active the gate shares its `SharedPreferences`
  /// file, so an unguarded read would leak the selector as a regular setting.
  bool _hidesGateRead(String key) => key == SettingsEngineGate.key;

  @override
  bool get initialized => _active.initialized;

  @override
  Future<void> init() async {
    _version = await _gate.read();
    // The legacy store is always initialized: it powers both the one-time seed
    // and an instant, lossless rollback.
    await _legacy.init();
    if (isMeta) {
      try {
        await _meta.init();
        await MetaSettingsSeeder(legacy: _legacy, meta: _meta).seedIfNeeded();
      } catch (error, stack) {
        // An unopenable database must not take the whole app down: serve this
        // session from the legacy engine. The gate is left untouched, so a later
        // launch with a healthy database retries v2.
        _log.e('failed to open the metadata engine, falling back to the legacy engine', error, stack);
        _version = SettingsEngineVersion.v1;
      }
    }
    _log.i('settings engine=${_version.name}');
  }

  /// Persists [version] and initializes the newly authoritative store.
  Future<void> activate(SettingsEngineVersion version) async {
    if (version == _version) return;

    // Initialize the incoming store before committing the switch. If opening it
    // fails (e.g. the database is unavailable), the gate, [_version] and the
    // active store all stay on the previous engine instead of pointing at a
    // broken one; the caller sees the error and the state remains consistent.
    final SettingsStore target = version == SettingsEngineVersion.v2 ? _meta : _legacy;
    if (!target.initialized) {
      await target.init();
    }

    if (!await _gate.write(version)) {
      // Refuse to commit a switch whose selector cannot be persisted: the stored
      // gate would still name the previous engine and silently override the
      // in-memory choice on the next launch.
      throw StateError('failed to persist the settings engine gate=${version.name}');
    }
    _version = version;
    if (isMeta) {
      await MetaSettingsSeeder(legacy: _legacy, meta: _meta).seedIfNeeded();
    }
    _log.i('settings engine switched to ${version.name}');
  }

  // lifecycle

  @override
  Future<void> reload() => _active.reload();

  @override
  Future<void> flush() => _active.flush();

  @override
  Future<bool> clear() async {
    final version = _version;
    final result = await _active.clear();
    // The gate key lives in the same SharedPreferences file as v1, so a v1 clear
    // wipes the selector; re-assert it. A failed re-assert is reported rather
    // than swallowed, otherwise the engine choice is silently lost.
    final gateWritten = await _gate.write(version);
    return result && gateWritten;
  }

  @override
  Future<bool> remove(String key) {
    if (key == SettingsEngineGate.key) return Future.value(true);
    return _active.remove(key);
  }

  // get

  @override
  Set<String> getKeys() => _active.getKeys().where((key) => key != SettingsEngineGate.key).toSet();

  @override
  Object? get(String key) => _hidesGateRead(key) ? null : _active.get(key);

  @override
  bool? getBool(String key) => _hidesGateRead(key) ? null : _active.getBool(key);

  @override
  int? getInt(String key) => _hidesGateRead(key) ? null : _active.getInt(key);

  @override
  double? getDouble(String key) => _hidesGateRead(key) ? null : _active.getDouble(key);

  @override
  String? getString(String key) => _hidesGateRead(key) ? null : _active.getString(key);

  @override
  List<String>? getStringList(String key) => _hidesGateRead(key) ? null : _active.getStringList(key);

  // set

  @override
  Future<bool> setBool(String key, bool value) => _ignoresGateWrite(key) ? Future.value(true) : _active.setBool(key, value);

  @override
  Future<bool> setInt(String key, int value) => _ignoresGateWrite(key) ? Future.value(true) : _active.setInt(key, value);

  @override
  Future<bool> setDouble(String key, double value) => _ignoresGateWrite(key) ? Future.value(true) : _active.setDouble(key, value);

  @override
  Future<bool> setString(String key, String value) => _ignoresGateWrite(key) ? Future.value(true) : _active.setString(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) => _ignoresGateWrite(key) ? Future.value(true) : _active.setStringList(key, value);
}
