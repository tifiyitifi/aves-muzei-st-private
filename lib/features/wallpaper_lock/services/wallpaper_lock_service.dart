import 'dart:async';

import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/wallpaper_lock/db/wallpaper_lock_store.dart';
import 'package:aves/features/wallpaper_lock/log.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/security_service.dart';
import 'package:flutter/foundation.dart';

/// The PIN-protected locks of the wallpaper surfaces.
///
/// **This is not a security boundary.** The PIN only stops a casual tap from
/// editing the visible range, temporarily ignoring it, or leaving the locked
/// wallpaper group; any app with the same access, `adb` or a rooted device can
/// read or bypass the store. It exists so the app cannot be knocked into a state
/// its owner did not want while someone else is holding the phone.
///
/// The two locks are independent data:
///
/// - **Visible range lock** lives on the range row itself
///   (`visible_ranges.locked`), exactly like the gallery's own padlock. This
///   service therefore has no state for it: it only verifies the PIN when a
///   locked range is unlocked or a locked range is temporarily ignored.
/// - **Group switch lock** lives here: one flag plus the id of the group that was
///   locked. It is persisted in AppMeta, so it survives closing the page, leaving
///   the app and a process restart; only unlocking (with the PIN), clearing the
///   app's data or reinstalling clears it.
///
/// Each kind has its own 4-digit PIN, defaulting to [defaultPin] until one is
/// written. The PINs live in the platform's encrypted preferences (the vault's
/// store) and are never part of settings import/export. There is no "forgot PIN"
/// flow: clearing the app's data is the only reset, which also removes the
/// encrypted store and returns both PINs to the default.
class WallpaperLockService extends ChangeNotifier {
  static const String defaultPin = '1234';

  /// Injected by tests; production reads the app-wide services.
  final SecurityService? _injectedSecurity;
  final WallpaperLockStore? _injectedStore;

  WallpaperLockStore? _store;
  Future<void>? _initFuture;

  bool _groupSwitchLocked = false;
  String? _groupSwitchGroupId;

  new({SecurityService? security, WallpaperLockStore? store}) : _injectedSecurity = security, _injectedStore = store;

  SecurityService get _security => _injectedSecurity ?? securityService;

  /// Loads the persisted group lock.
  ///
  /// Runs before the first frame, so a page never reads "unlocked" for a lock
  /// that is actually on. A failed read leaves the lock off: a database error
  /// must not lock the user out of their own settings.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      _store = _injectedStore ?? WallpaperLockStore(await getIt<AppDatabaseProvider>().open());
      final lock = await _store!.readGroupLock();
      _groupSwitchLocked = lock.locked;
      _groupSwitchGroupId = lock.groupId;
      notifyListeners();
      // The bar baked before this app run may predate the lock: refresh it once.
      unawaited(_refreshBar());
    } catch (error, stack) {
      wallpaperLockLog.e('failed to load the wallpaper locks', error, stack);
    }
  }

  /// Whether switching the wallpaper group is locked.
  bool get groupSwitchLocked => _groupSwitchLocked;

  /// The group that was showing when the switch lock was set, if any.
  String? get groupSwitchLockedGroupId => _groupSwitchGroupId;

  /// Whether [pin] is the current PIN of [kind].
  ///
  /// An unwritten PIN means [defaultPin]. The comparison is plain equality: as
  /// the class doc says, this is a gate, not cryptography.
  Future<bool> verify(WallpaperLockKind kind, String pin) async {
    try {
      final stored = await _security.readValue<String>(WallpaperLockStore.pinKeyOf(kind)) ?? defaultPin;
      return stored == pin;
    } catch (error, stack) {
      wallpaperLockLog.w('failed to read the pin of $kind', error, stack);
      return false;
    }
  }

  /// Replaces the PIN of [kind], after proving the current one.
  Future<bool> changePin(WallpaperLockKind kind, {required String currentPin, required String nextPin}) async {
    if (nextPin.length != 4 || !await verify(kind, currentPin)) {
      wallpaperLockLog.w('pin change refused kind=$kind reason=${nextPin.length != 4 ? 'invalid-length' : 'wrong-current'}');
      return false;
    }
    try {
      await _security.writeValue<String>(WallpaperLockStore.pinKeyOf(kind), nextPin);
      wallpaperLockLog.i('pin changed kind=$kind');
      return true;
    } catch (error, stack) {
      wallpaperLockLog.w('failed to write the pin of $kind', error, stack);
      return false;
    }
  }

  /// Locks the group switching, recording the group on screen.
  ///
  /// Locking needs no PIN: it only adds protection, and the user proves the PIN
  /// the first time an unlock is asked for. A lock with no group id (group 0) is
  /// refused, because there would be nothing to browse.
  Future<void> lockGroup(String groupId) async {
    final store = _store;
    if (store == null || groupId.isEmpty) return;
    await store.writeGroupLock(locked: true, groupId: groupId);
    _groupSwitchLocked = true;
    _groupSwitchGroupId = groupId;
    wallpaperLockLog.i('group lock set group=$groupId');
    _changed();
  }

  /// Clears the group lock when [pin] matches.
  Future<bool> unlockGroup(String pin) async {
    final store = _store;
    if (store == null || !_groupSwitchLocked) return false;
    if (!await verify(WallpaperLockKind.groupSwitch, pin)) {
      wallpaperLockLog.w('group unlock refused: wrong pin');
      return false;
    }
    await store.writeGroupLock(locked: false);
    _groupSwitchLocked = false;
    _groupSwitchGroupId = null;
    wallpaperLockLog.i('group lock cleared');
    _changed();
    return true;
  }

  void _changed() {
    notifyListeners();
    unawaited(_refreshBar());
  }

  /// Makes the notification grey or re-enable its group buttons.
  ///
  /// Only the group-switch lock changes what the bar offers; a failure is logged
  /// and swallowed, because the Dart-side guard still refuses the action.
  Future<void> _refreshBar() async {
    try {
      await wallpaperEngineLink.refreshLock();
    } catch (error, stack) {
      wallpaperLockLog.w('failed to refresh the wallpaper bar', error, stack);
    }
  }
}

/// The process-wide lock state.
final wallpaperLockService = WallpaperLockService();
