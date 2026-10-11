import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/engine/value_guard.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/model/settings/settings.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// Applies catalog edits to the active settings store.
///
/// A value is validated by [MetaValueGuard] and written through
/// `SettingsAccess.set`, which routes to whichever engine is authoritative and
/// emits the usual change event.
class MetaSettingsEngine {
  const new();

  void apply(SettingDef def, Object? value) {
    final Object? guarded;
    try {
      guarded = MetaValueGuard.guard(def, value);
    } on MetaSettingValueException catch (error) {
      _log.w('rejected value for ${def.key}: $error');
      return;
    }
    settings.set(def.key, guarded);
  }
}

const metaSettingsEngine = MetaSettingsEngine();
