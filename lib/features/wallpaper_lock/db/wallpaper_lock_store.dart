import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:equatable/equatable.dart';

/// The persisted group-switch lock: whether it is on, and the group it froze.
///
/// [groupId] is only meaningful while [locked], but the pair is read and written
/// together so a crash between two writes cannot leave a lock pointing at no
/// group.
class GroupSwitchLockSnapshot extends Equatable {
  final bool locked;
  final String? groupId;

  const new({required this.locked, this.groupId});

  @override
  List<Object?> get props => [locked, groupId];
}

/// Persistence of the wallpaper locks.
///
/// The group-switch lock is an ordinary AppMeta value, like the wallpaper's other
/// switches, so the feature needs no table and no schema migration. The PINs are
/// deliberately not here: they live in the platform's encrypted preferences
/// through `SecurityService`, the same store the vault uses.
///
/// The visible range lock is not stored here either: it is the range's own
/// `locked` column, the same state the padlock on the range page edits.
class WallpaperLockStore {
  /// Catalog id of the visible-range password row.
  ///
  /// The lock itself is the range's `locked` column; this key only identifies the
  /// settings entry, which is why it is not read or written here.
  static const keyVisibleRangeLockId = 'wallpaper.lock.visibleRange.locked';

  static const keyGroupSwitchLocked = 'wallpaper.lock.groupSwitch.locked';
  static const keyGroupSwitchGroupId = 'wallpaper.lock.groupSwitch.groupId';

  /// Encrypted-preferences keys of the PINs.
  ///
  /// They must never be exported with settings: a backup would carry the lock's
  /// secret to another device, and the encrypted store is device-bound anyway.
  static const keyVisibleRangePin = 'wallpaper.lock.visibleRange.pin';
  static const keyGroupSwitchPin = 'wallpaper.lock.groupSwitch.pin';

  static String pinKeyOf(WallpaperLockKind kind) => switch (kind) {
        WallpaperLockKind.visibleRange => keyVisibleRangePin,
        WallpaperLockKind.groupSwitch => keyGroupSwitchPin,
      };

  final AppDatabase db;

  new(this.db);

  /// The group lock. A missing or unreadable value means unlocked.
  Future<GroupSwitchLockSnapshot> readGroupLock() async {
    final values = await AppMetaStore(db).read({keyGroupSwitchLocked, keyGroupSwitchGroupId});
    final locked = values[keyGroupSwitchLocked] == 'true';
    final groupId = values[keyGroupSwitchGroupId];
    return GroupSwitchLockSnapshot(
      locked: locked,
      groupId: locked && groupId != null && groupId.isNotEmpty ? groupId : null,
    );
  }

  /// Writes the lock and its group together; unlocking drops the group.
  Future<void> writeGroupLock({required bool locked, String? groupId}) => AppMetaStore(db).write({
        keyGroupSwitchLocked: locked ? 'true' : 'false',
        keyGroupSwitchGroupId: locked && groupId != null && groupId.isNotEmpty ? groupId : '',
      });
}
