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
///
/// This is the write path for generic `toggle`/`enumPick` defs (and the
/// `mutator` defs). A `custom` editor that needs multi-key or async side
/// effects calls the typed setters directly instead, skipping the guard.
///
/// [apply] cannot report a persistence failure: it writes through
/// `SettingsAccess.set`, which notifies synchronously and drops the store's
/// future. The v2 store therefore resyncs its cache on a failed write without
/// re-emitting, and a listener keeps the optimistic value until the next reload
/// (see `MetaSettingsStore`). Keeping [apply] synchronous is deliberate; only
/// these defs are at risk, and batch paths `await flush()`.
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

    final mutator = def.mutator;
    if (mutator != null) {
      mutator(settings, guarded);
      return;
    }
    // Enums are persisted by name, like the typed setters do.
    settings.set(def.key, guarded is Enum ? guarded.name : guarded);
  }
}

const metaSettingsEngine = MetaSettingsEngine();
