abstract class SettingsStore {
  bool get initialized;

  Future<void> init();

  Future<void> reload();

  /// Ensures writes issued before this call are persisted. Best effort: the
  /// default is a no-op, engines with an explicit write barrier override it.
  Future<void> flush() async {}

  Future<bool> clear();

  Future<bool> remove(String key);

  // get

  Set<String> getKeys();

  Object? get(String key);

  bool? getBool(String key);

  int? getInt(String key);

  double? getDouble(String key);

  String? getString(String key);

  List<String>? getStringList(String key);

  // set

  Future<bool> setBool(String key, bool value);

  Future<bool> setInt(String key, int value);

  Future<bool> setDouble(String key, double value);

  Future<bool> setString(String key, String value);

  Future<bool> setStringList(String key, List<String> value);
}
