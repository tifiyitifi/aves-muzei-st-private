import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';

/// Thrown when a value does not fit a def's widget kind.
class MetaSettingValueException implements Exception {
  final String message;

  const new(this.message);

  @override
  String toString() => 'MetaSettingValueException: $message';
}

/// Validates a value before it reaches the store.
///
/// The renderer already produces well-typed values, so this is a safety net that
/// also documents each widget kind's contract and keeps a stray caller from
/// persisting an out-of-domain value.
abstract final class MetaValueGuard {
  static Object? guard(SettingDef def, Object? value) {
    switch (def.widgetKind) {
      case SettingWidgetKind.toggle:
        if (value is! bool) {
          throw MetaSettingValueException('${def.key} expects a bool, got ${value.runtimeType}');
        }
        return value;
      case SettingWidgetKind.enumPick:
        final names = def.enumValues?.map((v) => v.name).toSet() ?? const <String>{};
        if (value is! String || !names.contains(value)) {
          throw MetaSettingValueException('${def.key} expects one of $names, got $value');
        }
        return value;
      case SettingWidgetKind.custom:
        // The custom editor owns its value domain.
        return value;
    }
  }
}
