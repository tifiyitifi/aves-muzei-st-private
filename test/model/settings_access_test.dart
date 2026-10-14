import 'dart:convert';

import 'package:aves_model/aves_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory [SettingsStore] good enough to observe [SettingsAccess.set].
class _MemoryStore implements SettingsStore {
  final Map<String, Object> _values = {};

  @override
  bool get initialized => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Set<String> getKeys() => _values.keys.toSet();

  @override
  Object? get(String key) => _values[key];

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  List<String>? getStringList(String key) => (_values[key] as List?)?.cast<String>().toList();

  @override
  Future<bool> setBool(String key, bool value) async => _set(key, value);

  @override
  Future<bool> setInt(String key, int value) async => _set(key, value);

  @override
  Future<bool> setDouble(String key, double value) async => _set(key, value);

  @override
  Future<bool> setString(String key, String value) async => _set(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) async => _set(key, value);

  bool _set(String key, Object value) {
    _values[key] = value;
    return true;
  }
}

/// A minimal [SettingsAccess] host that records the keys it notified.
class _Subject with ChangeNotifier, SettingsAccess {
  final _store = _MemoryStore();
  final List<String> changes = [];

  @override
  SettingsStore get store => _store;

  @override
  bool get initialized => _store.initialized;

  @override
  Stream<SettingsChangedEvent> get updateStream => const Stream.empty();

  @override
  void notifyKeyChange(String key, Object? oldValue, Object? newValue, {bool recordRecent = true}) => changes.add(key);
}

void main() {
  test('a List<dynamic> of strings is persisted as a string list', () {
    final subject = _Subject();
    final dynamic decoded = jsonDecode('["a","b"]');
    expect(decoded, isNot(isA<List<String>>()));

    subject.set('k', decoded);

    expect(subject.store.getStringList('k'), ['a', 'b']);
    expect(subject.changes, ['k']);
  });

  test('a list holding non-string elements neither persists nor notifies', () {
    final subject = _Subject();
    final dynamic decoded = jsonDecode('[1,2]');

    subject.set('k', decoded);

    expect(subject.store.get('k'), isNull);
    expect(subject.changes, isEmpty, reason: 'a listener must not observe a change that was not persisted');
  });

  test('an unsupported value type neither persists nor notifies', () {
    final subject = _Subject();

    subject.set('k', DateTime(2020));

    expect(subject.store.get('k'), isNull);
    expect(subject.changes, isEmpty);
  });
}
