import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';

/// Persistence of the two wallpaper locks.
///
/// The on/off flags are ordinary AppMeta values, like the wallpaper's other
/// switches, so the feature needs no table and no schema migration. The PINs are
/// deliberately not here: they live in the platform's encrypted preferences
/// through `SecurityService`, the same store the vault uses.
class WallpaperLockStore {
  static const keyVisibleRangeEnabled = 'wallpaper.lock.visibleRange.enabled';
  static const keyGroupSwitchEnabled = 'wallpaper.lock.groupSwitch.enabled';

  /// Encrypted-preferences keys of the PINs.
  ///
  /// They must never be exported with settings: a backup would carry the lock's
  /// secret to another device, and the encrypted store is device-bound anyway.
  static const keyVisibleRangePin = 'wallpaper.lock.visibleRange.pin';
  static const keyGroupSwitchPin = 'wallpaper.lock.groupSwitch.pin';

  static String enabledKeyOf(WallpaperLockKind kind) => switch (kind) {
        WallpaperLockKind.visibleRange => keyVisibleRangeEnabled,
        WallpaperLockKind.groupSwitch => keyGroupSwitchEnabled,
      };

  static String pinKeyOf(WallpaperLockKind kind) => switch (kind) {
        WallpaperLockKind.visibleRange => keyVisibleRangePin,
        WallpaperLockKind.groupSwitch => keyGroupSwitchPin,
      };

  final AppDatabase db;

  new(this.db);

  /// The kinds that are switched on. A missing value means off.
  Future<Set<WallpaperLockKind>> readEnabled() async {
    final values = await AppMetaStore(db).read({keyVisibleRangeEnabled, keyGroupSwitchEnabled});
    return {
      for (final kind in WallpaperLockKind.values)
        if (values[enabledKeyOf(kind)] == 'true') kind,
    };
  }

  Future<void> writeEnabled(WallpaperLockKind kind, bool enabled) => AppMetaStore(db).write({enabledKeyOf(kind): enabled ? 'true' : 'false'});
}
