import 'package:aves_model/aves_model.dart';
import 'package:aves_utils/aves_utils.dart';
import 'package:collection/collection.dart';

mixin SettingsAccess {
  bool get initialized;

  SettingsStore get store;

  Stream<SettingsChangedEvent> get updateStream;

  /// Emits a change event for [key]. When [recordRecent] is false, a
  /// programmatic replay is not treated as a user edit and is kept out of the
  /// recent-changed list.
  void notifyKeyChange(String key, Object? oldValue, Object? newValue, {bool recordRecent = true});

  void notifyListeners();

  bool hasValueChanged(Object? oldValue, Object? newValue) {
    if (oldValue is Iterable && newValue is Iterable) {
      return !const DeepCollectionEquality().equals(oldValue, newValue);
    }
    return oldValue != newValue;
  }

  void set(String key, Object? newValue) {
    var oldValue = store.get(key);
    var handled = true;
    if (newValue == null) {
      store.remove(key);
    } else if (newValue is String) {
      oldValue = getString(key);
      store.setString(key, newValue);
    } else if (newValue is List) {
      final list = _asStringList(newValue);
      if (list == null) {
        handled = false;
      } else {
        oldValue = getStringList(key);
        newValue = list;
        store.setStringList(key, list);
      }
    } else if (newValue is int) {
      oldValue = getInt(key);
      store.setInt(key, newValue);
    } else if (newValue is double) {
      oldValue = getDouble(key);
      store.setDouble(key, newValue);
    } else if (newValue is bool) {
      oldValue = getBool(key);
      store.setBool(key, newValue);
    } else {
      handled = false;
    }
    // Only notify a value the store accepted: an unhandled value (an
    // unsupported type or a non-string list) must not reach a listener. This is
    // not a durability check — a store may persist asynchronously, so the
    // notified value can still fail to reach disk afterwards.
    if (handled && hasValueChanged(oldValue, newValue)) {
      notifyKeyChange(key, oldValue, newValue);
      notifyListeners();
    }
  }

  // getters

  bool? getBool(String key) {
    try {
      return store.getBool(key);
    } catch (error) {
      // ignore, could be obsolete value of different type
      return null;
    }
  }

  int? getInt(String key) {
    try {
      return store.getInt(key);
    } catch (error) {
      // ignore, could be obsolete value of different type
      return null;
    }
  }

  double? getDouble(String key) {
    try {
      return store.getDouble(key);
    } catch (error) {
      // ignore, could be obsolete value of different type
      return null;
    }
  }

  String? getString(String key) {
    try {
      return store.getString(key);
    } catch (error) {
      // ignore, could be obsolete value of different type
      return null;
    }
  }

  List<String>? getStringList(String key) {
    try {
      return store.getStringList(key);
    } catch (error) {
      // ignore, could be obsolete value of different type
      return null;
    }
  }

  T getEnumOrDefault<T extends Enum>(String key, T defaultValue, Iterable<T> values) {
    try {
      return values.safeByName(store.getString(key)) ?? defaultValue;
    } catch (error) {
      // ignore, could be obsolete value of different type
      return defaultValue;
    }
  }

  List<T> getEnumListOrDefault<T extends Enum>(String key, List<T> defaultValue, Iterable<T> values) {
    return store.getStringList(key)?.map((s) => values.safeByName(s)).nonNulls.toList() ?? defaultValue;
  }
}

/// Eagerly materializes [value] as a string list, or null when it holds a
/// non-string element. A lazy `cast` would only throw when the store later reads
/// it, far from [SettingsAccess.set], turning a bad value into a delayed crash.
List<String>? _asStringList(List value) {
  try {
    return List<String>.from(value);
  } catch (error) {
    return null;
  }
}
