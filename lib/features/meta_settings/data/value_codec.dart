import 'dart:convert';

import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// Encodes and decodes metadata-setting values to their TEXT column form.
///
/// Decoding never throws: malformed persisted data logs a warning and yields
/// null, so the typed getters fall back to defaults instead of crashing.
abstract final class MetaSettingsValueCodec {
  static String encodeBool(bool value) => value ? '1' : '0';

  static String encodeInt(int value) => '$value';

  static String encodeDouble(double value) => value.toString();

  static String encodeString(String value) => value;

  static String encodeStringList(List<String> value) => jsonEncode(value);

  static bool? decodeBool(String? raw) => switch (raw) {
        '1' => true,
        '0' => false,
        _ => null,
      };

  static int? decodeInt(String? raw) => raw == null ? null : int.tryParse(raw);

  static double? decodeDouble(String? raw) => raw == null ? null : double.tryParse(raw);

  static String? decodeString(String? raw) => raw;

  static List<String>? decodeStringList(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      // `List.cast` is lazy: it returns a view that only throws when an element
      // is read, which would break the "never throws" contract far from here.
      // Validate eagerly and materialize a real list instead.
      if (decoded is List && decoded.every((element) => element is String)) {
        return List<String>.from(decoded);
      }
      _log.w('failed to decode string list raw=$raw');
      return null;
    } catch (error) {
      _log.w('failed to decode string list raw=$raw error=$error');
      return null;
    }
  }
}
