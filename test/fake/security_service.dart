import 'package:aves/services/security_service.dart';
import 'package:flutter/foundation.dart';
import 'package:test/fake.dart';

class FakeSecurityService extends Fake implements SecurityService {
  final Map<String, Object?> _values = {};

  @override
  Future<bool> writeValue<T>(String key, T? value) {
    value == null ? _values.remove(key) : _values[key] = value;
    return SynchronousFuture(true);
  }

  @override
  Future<T?> readValue<T>(String key) => SynchronousFuture(_values[key] as T?);
}
