import 'dart:async';

import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/wallpaper_lock/db/wallpaper_lock_store.dart';
import 'package:aves/features/wallpaper_lock/log.dart';
import 'package:aves/features/wallpaper_lock/model/wallpaper_lock_kind.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/security_service.dart';
import 'package:flutter/widgets.dart';

/// The two optional PIN gates of the wallpaper surfaces.
///
/// **This is not a security boundary.** The PIN only stops a casual tap from
/// editing the visible range or switching the playing group; any app with the
/// same access, `adb` or a rooted device can read or bypass the store. It exists
/// so the app cannot be knocked into a state its owner did not want while
/// someone else is holding the phone.
///
/// - Each kind has its own 4-digit PIN, defaulting to [defaultPin] until one is
///   written. The PINs live in the platform's encrypted preferences (the vault's
///   store) and are never part of settings import/export.
/// - There is no "forgot PIN" flow: clearing the app's data is the only reset,
///   which also removes the encrypted store and returns both locks to off.
/// - A correct PIN unlocks that kind for the current foreground session only.
///   Backgrounding the app (`paused`) locks it again; a process restart starts
///   locked.
class WallpaperLockService extends ChangeNotifier with WidgetsBindingObserver {
  static const String defaultPin = '1234';

  /// Injected by tests; production reads the app-wide services.
  final SecurityService? _injectedSecurity;
  final WallpaperLockStore? _injectedStore;

  WallpaperLockStore? _store;
  Future<void>? _initFuture;
  bool _observing = false;

  final Set<WallpaperLockKind> _enabled = {};
  final Set<WallpaperLockKind> _unlocked = {};

  new({SecurityService? security, WallpaperLockStore? store}) : _injectedSecurity = security, _injectedStore = store;

  SecurityService get _security => _injectedSecurity ?? securityService;

  /// Loads both flags and starts following the app's lifecycle.
  ///
  /// Runs before the first frame, so a page never reads "off" for a lock that is
  /// actually on. A failed read leaves both locks off: a database error must not
  /// lock the user out of their own settings.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      _store = _injectedStore ?? WallpaperLockStore(await getIt<AppDatabaseProvider>().open());
      final enabled = await _store!.readEnabled();
      _enabled
        ..clear()
        ..addAll(enabled);
      if (!_observing) {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      }
      notifyListeners();
      // The bar baked before this app run may predate the lock: refresh it once.
      unawaited(_refreshBar());
    } catch (error, stack) {
      wallpaperLockLog.e('failed to load the wallpaper locks', error, stack);
    }
  }

  bool isEnabled(WallpaperLockKind kind) => _enabled.contains(kind);

  bool isUnlocked(WallpaperLockKind kind) => _unlocked.contains(kind);

  /// Whether [kind] is on and has not been unlocked this session.
  bool isLocked(WallpaperLockKind kind) => isEnabled(kind) && !isUnlocked(kind);

  bool get visibleRangeLocked => isLocked(WallpaperLockKind.visibleRange);

  bool get groupSwitchLocked => isLocked(WallpaperLockKind.groupSwitch);

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

  /// Unlocks [kind] for this foreground session when [pin] matches.
  Future<bool> unlock(WallpaperLockKind kind, String pin) async {
    if (!await verify(kind, pin)) return false;
    _unlocked.add(kind);
    _changed(kind);
    return true;
  }

  /// Locks [kind] again without leaving the app.
  void relock(WallpaperLockKind kind) {
    if (!_unlocked.remove(kind)) return;
    _changed(kind);
  }

  /// Turns [kind] on, locked from the start.
  ///
  /// Enabling needs no PIN: it only adds protection, and the user proves the PIN
  /// the first time a protected action asks for one. The current PIN is kept, so
  /// turning the lock off and on again keeps a changed PIN.
  Future<void> enable(WallpaperLockKind kind) async {
    final store = _store;
    if (store == null || _enabled.contains(kind)) return;
    await store.writeEnabled(kind, true);
    _enabled.add(kind);
    _unlocked.remove(kind);
    _changed(kind);
  }

  /// Turns [kind] off when [pin] matches.
  Future<bool> disable(WallpaperLockKind kind, String pin) async {
    final store = _store;
    if (store == null || !_enabled.contains(kind)) return false;
    if (!await verify(kind, pin)) return false;
    await store.writeEnabled(kind, false);
    _enabled.remove(kind);
    _unlocked.remove(kind);
    _changed(kind);
    return true;
  }

  /// Replaces the PIN of [kind], after proving the current one.
  Future<bool> changePin(WallpaperLockKind kind, {required String currentPin, required String nextPin}) async {
    if (nextPin.length != 4 || !await verify(kind, currentPin)) return false;
    try {
      await _security.writeValue<String>(WallpaperLockStore.pinKeyOf(kind), nextPin);
      return true;
    } catch (error, stack) {
      wallpaperLockLog.w('failed to write the pin of $kind', error, stack);
      return false;
    }
  }

  void _changed(WallpaperLockKind kind) {
    notifyListeners();
    if (kind == WallpaperLockKind.groupSwitch) unawaited(_refreshBar());
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    if (_unlocked.isEmpty) return;
    // Leaving the app ends the unlocked session: the next person to pick the
    // phone must prove the PIN again.
    _unlocked.clear();
    notifyListeners();
    unawaited(_refreshBar());
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    super.dispose();
  }
}

/// The process-wide lock state.
final wallpaperLockService = WallpaperLockService();
