import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// One-time `v1 -> v2` seeding.
///
/// When the metadata engine first becomes authoritative, the legacy store's
/// user settings are copied into it, so flipping the default engine never
/// silently resets an upgrading user. A marker in `appMeta` makes it truly
/// one-shot: a later deliberate clear of v2 is not resurrected. Until the marker
/// is written, each attempt copies the keys still missing, so a partial failure
/// resumes on the next init instead of freezing the rest of the seed.
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

    // Retry-safe: copy only the keys the metadata store does not already hold.
    // An attempt that aborted mid-way therefore resumes on the next init and
    // fills in the missing keys, while a value the user has since edited in v2
    // (or already copied by an earlier attempt) is never overwritten.
    final existing = meta.getKeys();
    // the gate lives in the legacy store's SharedPreferences but is not a
    // setting: never copy it into the metadata store
    final keys = legacy
        .getKeys()
        .whereNot(SettingKeys.isInternalKey)
        .where((key) => key != SettingsEngineGate.key && !existing.contains(key))
        .toList();
    var copied = 0;
    for (final key in keys) {
      final value = legacy.get(key);
      if (value == null) continue;
      if (!await meta.put(key, value)) {
        // leave the marker unwritten so a later init retries the seed
        _log.w('failed to seed key=$key, aborting before writing the seed marker');
        return;
      }
      copied++;
    }
    if (copied > 0) {
      _log.i('seeded $copied settings from the legacy engine');
    }

    await appMeta.write({markerKey: 'true'});
  }
}
