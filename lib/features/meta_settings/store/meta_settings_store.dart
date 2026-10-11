import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/data/value_codec.dart';
import 'package:aves/features/meta_settings/db/settings_dao.dart';
import 'package:aves/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// The metadata engine's `SettingsStore`: Drift-backed sparse overrides.
///
/// Values are loaded once at [init] into an in-memory cache so the typed getters
/// stay synchronous (the same contract as `SharedPreferences`); writes update
/// the cache and persist asynchronously. A failed write rolls the cache back to
/// the persisted state, so memory never diverges from the database.
class MetaSettingsStore implements SettingsStore {
  /// Optional injected database, used by tests (which never register the
  /// app-wide [AppDatabaseProvider]).
  new({this.injectedDatabase});

  final AppDatabase? injectedDatabase;
  AppDatabase? _db;
  Map<String, MetaSettingRow>? _cache;

  /// The backing database, available after [init]; the seeder reads/writes its
  /// one-time marker through `AppMetaStore`.
  AppDatabase? get database => _db;

  @override
  bool get initialized => _cache != null;

  @override
  Future<void> init() async {
    final db = injectedDatabase ?? await getIt<AppDatabaseProvider>().open();
    _db = db;
    _cache = await MetaSettingsDao(db).loadAll();
  }

  @override
  Future<void> reload() async {
    final db = _db;
    if (db == null) return;
    _cache = await MetaSettingsDao(db).loadAll();
  }

  @override
  Future<bool> clear() async {
    final db = _db;
    if (db == null) return false;
    final previous = _cache;
    _cache = <String, MetaSettingRow>{};
    try {
      await MetaSettingsDao(db).clear();
    } catch (error, stack) {
      _cache = previous;
      _log.e('failed to clear settings, cache rolled back', error, stack);
      return false;
    }
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    final db = _db;
    if (db == null) return false;
    final previous = _cache?[key];
    _cache?.remove(key);
    try {
      await MetaSettingsDao(db).remove(key);
    } catch (error, stack) {
      if (previous != null) _cache?[key] = previous;
      _log.e('failed to remove setting key=$key, cache rolled back', error, stack);
      return false;
    }
    return true;
  }

  // get

  @override
  Set<String> getKeys() => _cache?.keys.toSet() ?? <String>{};

  @override
  Object? get(String key) {
    final row = _cache?[key];
    if (row == null) return null;
    return switch (row.type) {
      SettingValueType.bool => MetaSettingsValueCodec.decodeBool(row.raw),
      SettingValueType.int => MetaSettingsValueCodec.decodeInt(row.raw),
      SettingValueType.double => MetaSettingsValueCodec.decodeDouble(row.raw),
      SettingValueType.string => MetaSettingsValueCodec.decodeString(row.raw),
      SettingValueType.stringList => MetaSettingsValueCodec.decodeStringList(row.raw),
      SettingValueType.enumeration => MetaSettingsValueCodec.decodeString(row.raw),
    };
  }

  @override
  bool? getBool(String key) => _typed(key, SettingValueType.bool, MetaSettingsValueCodec.decodeBool);

  @override
  int? getInt(String key) => _typed(key, SettingValueType.int, MetaSettingsValueCodec.decodeInt);

  @override
  double? getDouble(String key) => _typed(key, SettingValueType.double, MetaSettingsValueCodec.decodeDouble);

  @override
  String? getString(String key) => _typed(key, SettingValueType.string, MetaSettingsValueCodec.decodeString);

  @override
  List<String>? getStringList(String key) => _typed(key, SettingValueType.stringList, MetaSettingsValueCodec.decodeStringList);

  // set

  @override
  Future<bool> setBool(String key, bool value) => _put(key, SettingValueType.bool, MetaSettingsValueCodec.encodeBool(value));

  @override
  Future<bool> setInt(String key, int value) => _put(key, SettingValueType.int, MetaSettingsValueCodec.encodeInt(value));

  @override
  Future<bool> setDouble(String key, double value) => _put(key, SettingValueType.double, MetaSettingsValueCodec.encodeDouble(value));

  @override
  Future<bool> setString(String key, String value) => _put(key, SettingValueType.string, MetaSettingsValueCodec.encodeString(value));

  @override
  Future<bool> setStringList(String key, List<String> value) => _put(key, SettingValueType.stringList, MetaSettingsValueCodec.encodeStringList(value));

  /// Writes [value] by its runtime type. Not part of [SettingsStore]: used by
  /// the one-time legacy seed to copy a heterogeneous value set verbatim.
  ///
  /// Returns whether the value was persisted, so the seed can abort before
  /// marking itself done when a write fails.
  Future<bool> put(String key, Object? value) async {
    if (value == null) return remove(key);
    if (value is bool) return setBool(key, value);
    if (value is int) return setInt(key, value);
    if (value is double) return setDouble(key, value);
    if (value is String) return setString(key, value);
    if (value is List<String>) return setStringList(key, value);
    _log.w('skipped seeding of unsupported value for key=$key');
    return true;
  }

  T? _typed<T>(String key, SettingValueType expected, T? Function(String) decode) {
    final row = _cache?[key];
    if (row == null || row.type != expected) return null;
    return decode(row.raw);
  }

  Future<bool> _put(String key, SettingValueType type, String raw) async {
    final db = _db;
    if (db == null) return false;
    final cache = _cache;
    final previous = cache?[key];
    cache?[key] = (type: type, raw: raw);
    try {
      await MetaSettingsDao(db).upsert(key, type, raw);
    } catch (error, stack) {
      if (previous != null) {
        cache?[key] = previous;
      } else {
        cache?.remove(key);
      }
      _log.e('failed to persist setting key=$key, cache rolled back', error, stack);
      return false;
    }
    return true;
  }
}
