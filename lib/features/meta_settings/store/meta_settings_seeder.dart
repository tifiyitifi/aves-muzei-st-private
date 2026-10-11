import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// One-time `v1 -> v2` seeding.
///
/// When the metadata engine first becomes authoritative and its value table is
/// empty, the legacy store's user settings are copied verbatim, so flipping the
/// default engine never silently resets an upgrading user. A marker in `appMeta`
/// makes it truly one-shot: a later deliberate clear of v2 is not resurrected.
class MetaSettingsSeeder {
  static const String markerKey = 'settings_engine_seeded_v2';

  final SettingsStore legacy;
  final MetaSettingsStore meta;

  new({required this.legacy, required this.meta});

  Future<void> seedIfNeeded() async {
    final db = meta.database;
    if (db == null) return;

    final appMeta = AppMetaStore(db);
    if ((await appMeta.read({markerKey}))[markerKey] == 'true') return;

    if (meta.isEmpty) {
      final keys = legacy.getKeys().whereNot(SettingKeys.isInternalKey).toList();
      var copied = 0;
      for (final key in keys) {
        final value = legacy.get(key);
        if (value == null) continue;
        await meta.put(key, value);
        copied++;
      }
      if (copied > 0) {
        _log.i('seeded $copied settings from the legacy engine');
      }
    }

    await appMeta.write({markerKey: 'true'});
  }
}
