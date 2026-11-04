import 'dart:async';

import 'package:aves/features/logging/log.dart';
import 'package:aves/features/media_ops/engine/media_op_keys.dart';
import 'package:aves/features/media_ops/model/media_op_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Log channel owned by this feature (never a shared catch-all).
const String mediaOpLogKey = 'log.media_ops';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> mediaOpDebugLogKeys = [mediaOpLogKey];

const _log = AreaKeyLog(mediaOpLogKey);

/// User-tunable parameters of media file operations, independent of the
/// settings engine (v1/v2). Values persist in `SharedPreferences` under the
/// `media_ops.*` namespace and fall back to the defaults below when absent or
/// unreadable, so a fresh install behaves as the fast pipeline without any
/// migration.
///
/// The singleton self-loads on construction; [init] exists for callers (and
/// tests) that need the persisted values before first read.
class MediaOpPrefs extends ChangeNotifier {
  /// Whether a system write request may be raised after a Media Store write was
  /// refused. Only a denial clears it, so the app asks at most once and then
  /// stays quiet until the user re-enables it.
  static const bool defaultAllowPermissionPrompt = true;

  MediaOpEngine _engine = MediaOpEngine.defaultEngine;

  bool _allowPermissionPrompt = defaultAllowPermissionPrompt;

  bool _loaded = false;

  /// Shared across callers so the constructor's eager load and an explicit
  /// [init] never race and overwrite each other's result.
  Future<void>? _initializing;

  new() {
    unawaited(init());
  }

  MediaOpEngine get engine => _engine;

  bool get allowPermissionPrompt => _allowPermissionPrompt;

  /// Whether persisted values have been read. Getters return defaults before.
  bool get isLoaded => _loaded;

  Future<void> init() => _initializing ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _engine = MediaOpEngine.tryParse(prefs.getString(MediaOpKeys.engine)) ?? MediaOpEngine.defaultEngine;
      _allowPermissionPrompt = prefs.getBool(MediaOpKeys.allowPermissionPrompt) ?? defaultAllowPermissionPrompt;
    } catch (error, stack) {
      _log.w('failed to load media op prefs, using defaults', error, stack);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEngine(MediaOpEngine engine) async {
    if (engine == _engine) return;
    _engine = engine;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(MediaOpKeys.engine, engine.name);
    } catch (error, stack) {
      _log.e('failed to persist media op engine=${engine.name}', error, stack);
    }
  }

  /// Persists that the user refused a system write request.
  ///
  /// Only the transition to `false` is interesting, so an operation that keeps
  /// reporting denials never rewrites the preference.
  Future<void> denyPermissionPrompt() async {
    if (!_allowPermissionPrompt) return;
    _allowPermissionPrompt = false;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(MediaOpKeys.allowPermissionPrompt, false);
    } catch (error, stack) {
      _log.e('failed to persist media op permission denial', error, stack);
    }
  }

  /// Lets the next operation ask for system write access again.
  Future<void> resetPermissionPrompt() async {
    if (_allowPermissionPrompt == defaultAllowPermissionPrompt) return;
    _allowPermissionPrompt = defaultAllowPermissionPrompt;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(MediaOpKeys.allowPermissionPrompt, defaultAllowPermissionPrompt);
    } catch (error, stack) {
      _log.e('failed to reset media op permission prompt', error, stack);
    }
  }
}

/// The app-wide media operation preferences (mirrors the `settings` and
/// `collectionPagingPrefs` singleton style).
final MediaOpPrefs mediaOpPrefs = MediaOpPrefs();
