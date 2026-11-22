import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/features/meta_settings/store/settings_store_router.dart';
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
  /// Optional router, used by tests. Production uses the app-wide singleton so
  /// the controller and `settings` agree on the active store.
  final SettingsStoreRouter? _injectedRouter;

  /// Optional sanitize step, used by tests: the real one reads device
  /// capabilities that need platform channels, and the switch itself does not.
  final Future<void> Function()? _injectedSanitize;

  new({SettingsStoreRouter? router, Future<void> Function()? sanitize})
      : _injectedRouter = router,
        _injectedSanitize = sanitize;

  SettingsStoreRouter get _router => _injectedRouter ?? settingsStoreRouter;

  SettingsEngineVersion get version => _router.version;

  bool get isMeta => version == SettingsEngineVersion.v2;

  Future<void> setVersion(SettingsEngineVersion next) async {
    final router = _router;
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

    replayDiff(settings, before, after);

    settings.resetResolvedLocale();
    await (_injectedSanitize ?? settings.sanitize)();
    settings.notifyListeners();
    notifyListeners();
  }

  /// Replays the values that differ between [before] and [after] to [settings]'
  /// update stream, so listeners re-apply to the newly authoritative values.
  ///
  /// The replayed keys are not user edits, so they are kept out of the
  /// recent-changed list; otherwise a single engine switch would mark every
  /// differing key as recently changed and flood search's suggestions.
  static void replayDiff(SettingsAccess settings, SettingsStore before, SettingsStore after) {
    final keys = <String>{...before.getKeys(), ...after.getKeys()}..remove(SettingsEngineGate.key);
    for (final key in keys) {
      final oldValue = before.get(key);
      final newValue = after.get(key);
      if (settings.hasValueChanged(oldValue, newValue)) {
        settings.notifyKeyChange(key, oldValue, newValue, recordRecent: false);
      }
    }
  }
}

/// The app-wide engine controller (mirrors the `settings` singleton style).
final SettingsEngineController settingsEngineController = SettingsEngineController();
