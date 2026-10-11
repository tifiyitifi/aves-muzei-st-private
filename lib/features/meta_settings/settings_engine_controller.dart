import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// UI-facing controller for the settings engine switch.
///
/// [SettingsStoreRouter.activate] alone swaps the store. On top of that, this
/// controller replays the values that differ between the two engines, so
/// `settings.updateStream` listeners (brightness, refresh rate, layout, ...)
/// re-apply to the newly authoritative values, then notifies so `SettingsHost`
/// swaps the surface.
class SettingsEngineController extends ChangeNotifier {
  SettingsEngineVersion get version => settingsStoreRouter.version;

  bool get isMeta => version == SettingsEngineVersion.v2;

  Future<void> setVersion(SettingsEngineVersion next) async {
    final router = settingsStoreRouter;
    if (next == router.version) return;

    final toMeta = next == SettingsEngineVersion.v2;
    final SettingsStore before = toMeta ? router.legacyStore : router.metaStore;
    final SettingsStore after = toMeta ? router.metaStore : router.legacyStore;

    try {
      await router.activate(next);
    } catch (error, stack) {
      // The router initializes the incoming store before committing the switch,
      // so a failure leaves us on the previous engine: report and re-apply
      // nothing, keeping the controller and the UI consistent.
      _log.e('failed to switch the settings engine to ${next.name}', error, stack);
      return;
    }

    final keys = <String>{...before.getKeys(), ...after.getKeys()}..remove(SettingsEngineGate.key);
    for (final key in keys) {
      final oldValue = before.get(key);
      final newValue = after.get(key);
      if (settings.hasValueChanged(oldValue, newValue)) {
        settings.notifyKeyChange(key, oldValue, newValue);
      }
    }

    settings.resetResolvedLocale();
    await settings.sanitize();
    settings.notifyListeners();
    notifyListeners();
  }
}

/// The app-wide engine controller (mirrors the `settings` singleton style).
final SettingsEngineController settingsEngineController = SettingsEngineController();
