import 'dart:async';

import 'package:aves/features/live_wallpaper/log.dart';
import 'package:aves/features/live_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/live_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/live_wallpaper/model/wallpaper_gestures.dart';
import 'package:aves/features/live_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/live_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent keys owned by the live-wallpaper feature.
///
/// Kept out of the shared `SettingKeys` registry: these settings are meaningful
/// only to this feature and must be readable by the headless background isolate
/// without booting the whole settings engine.
abstract final class WallpaperPrefsKeys {
  static const String sourceKind = 'live_wallpaper.source.kind';
  static const String sourceFilters = 'live_wallpaper.source.filters';
  static const String sourceSingleId = 'live_wallpaper.source.single_id';

  static const String effectsHomeBlur = 'live_wallpaper.effects.home_blur';
  static const String effectsHomeDim = 'live_wallpaper.effects.home_dim';
  static const String effectsHomeGrey = 'live_wallpaper.effects.home_grey';
  static const String effectsLockBlur = 'live_wallpaper.effects.lock_blur';
  static const String effectsLockDim = 'live_wallpaper.effects.lock_dim';
  static const String effectsLockGrey = 'live_wallpaper.effects.lock_grey';
  static const String effectsLink = 'live_wallpaper.effects.link';

  static const String gesturesDoubleTap = 'live_wallpaper.gestures.double_tap';
  static const String gesturesThreeFinger = 'live_wallpaper.gestures.three_finger';

  static const String autoIntervalSeconds = 'live_wallpaper.auto.interval_seconds';
  static const String autoOrdering = 'live_wallpaper.auto.ordering';
  static const String lastAdvancedAt = 'live_wallpaper.last_advanced_at';
  static const String currentIndex = 'live_wallpaper.current_index';

  static const String viewportX = 'live_wallpaper.viewport.x';
  static const String viewportY = 'live_wallpaper.viewport.y';
  static const String viewportZoom = 'live_wallpaper.viewport.zoom';
}

/// Feature settings shared by the UI, the controller and the background worker.
///
/// Follows the existing `ChangeNotifier` + `SharedPreferences` pattern: the
/// in-memory value updates before the write, so UI sliders feel immediate while
/// persistence happens in the background.
class WallpaperPrefs extends ChangeNotifier {
  static const double minViewportZoom = 1;
  static const double maxViewportZoom = 4;

  final Future<SharedPreferences> Function() _prefsProvider;

  WallpaperSourceScope _scope = WallpaperSourceScope();
  WallpaperEffectsConfig _effects = const WallpaperEffectsConfig();
  WallpaperGestures _gestures = const WallpaperGestures();
  WallpaperAutoAdvance _autoAdvance = const WallpaperAutoAdvance();
  int? _lastAdvancedAt;
  int _currentIndex = 0;
  double _viewportX = 0;
  double _viewportY = 0;
  double _viewportZoom = 1;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _initFuture;

  new({Future<SharedPreferences> Function()? prefsProvider}) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance {
    unawaited(init());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Loads persisted values once; concurrent callers share the same future.
  Future<void> init() => _initFuture ??= _doInit();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  WallpaperSourceScope get scope => _scope;

  WallpaperEffectsConfig get effects => _effects;

  WallpaperGestures get gestures => _gestures;

  WallpaperAutoAdvance get autoAdvance => _autoAdvance;

  int? get lastAdvancedAt => _lastAdvancedAt;

  int get currentIndex => _currentIndex;

  double get viewportX => _viewportX;

  double get viewportY => _viewportY;

  double get viewportZoom => _viewportZoom;

  bool get isLoaded => _loaded;

  Future<void> _doInit() async {
    try {
      final prefs = await _prefsProvider();
      _scope = WallpaperSourceScope(
        kind: WallpaperSourceKind.tryParse(_string(prefs, WallpaperPrefsKeys.sourceKind)) ?? WallpaperSourceKind.myPhotos,
        filters: _readFilters(prefs),
        singleEntryId: _positiveInt(prefs.getInt(WallpaperPrefsKeys.sourceSingleId)),
      );
      _effects = WallpaperEffectsConfig(
        home: _readEffects(prefs, 'home'),
        lock: _readEffects(prefs, 'lock'),
        link: prefs.getBool(WallpaperPrefsKeys.effectsLink) ?? false,
      );
      _gestures = WallpaperGestures(
        doubleTap: WallpaperTapAction.tryParse(_string(prefs, WallpaperPrefsKeys.gesturesDoubleTap)) ?? WallpaperGestures.defaultDoubleTap,
        threeFinger: WallpaperTapAction.tryParse(_string(prefs, WallpaperPrefsKeys.gesturesThreeFinger)) ?? WallpaperGestures.defaultThreeFinger,
      );
      _autoAdvance = WallpaperAutoAdvance(
        interval: WallpaperInterval.tryFromSeconds(prefs.getInt(WallpaperPrefsKeys.autoIntervalSeconds)) ?? WallpaperAutoAdvance.defaultInterval,
        ordering: WallpaperOrdering.tryParse(_string(prefs, WallpaperPrefsKeys.autoOrdering)) ?? WallpaperAutoAdvance.defaultOrdering,
      );
      _lastAdvancedAt = prefs.getInt(WallpaperPrefsKeys.lastAdvancedAt);
      final index = prefs.getInt(WallpaperPrefsKeys.currentIndex);
      _currentIndex = index == null || index < 0 ? 0 : index;
      _viewportX = _double(prefs, WallpaperPrefsKeys.viewportX) ?? 0;
      _viewportY = _double(prefs, WallpaperPrefsKeys.viewportY) ?? 0;
      _viewportZoom = _clampZoom(_double(prefs, WallpaperPrefsKeys.viewportZoom) ?? 1);
    } catch (error, stack) {
      wallpaperLog.w('failed to load live wallpaper prefs, using defaults', error, stack);
    }
    _loaded = true;
    _notify();
  }

  Future<void> setSourceScope(WallpaperSourceScope value) async {
    _scope = value;
    _notify();
    try {
      final prefs = await _prefsProvider();
      await prefs.setString(WallpaperPrefsKeys.sourceKind, value.kind.name);
      await prefs.setStringList(WallpaperPrefsKeys.sourceFilters, value.sortedFilterJson);
      if (value.singleEntryId != null) {
        await prefs.setInt(WallpaperPrefsKeys.sourceSingleId, value.singleEntryId!);
      } else {
        await prefs.remove(WallpaperPrefsKeys.sourceSingleId);
      }
    } catch (error, stack) {
      wallpaperLog.e('failed to persist live wallpaper source scope', error, stack);
    }
  }

  Future<void> setSourceKind(WallpaperSourceKind kind) => setSourceScope(_scope.copyWith(kind: kind));

  Future<void> setFilters(Set<CollectionFilter> filters) => setSourceScope(_scope.copyWith(filters: filters));

  Future<void> setSingleEntryId(int? entryId) => setSourceScope(
    _scope.copyWith(
      singleEntryId: entryId,
      clearSingleEntryId: entryId == null,
    ),
  );

  Future<void> setEffects(WallpaperEffectsConfig value) async {
    _effects = value;
    _notify();
    try {
      final prefs = await _prefsProvider();
      await prefs.setInt(WallpaperPrefsKeys.effectsHomeBlur, value.home.blur);
      await prefs.setInt(WallpaperPrefsKeys.effectsHomeDim, value.home.dim);
      await prefs.setInt(WallpaperPrefsKeys.effectsHomeGrey, value.home.grey);
      await prefs.setInt(WallpaperPrefsKeys.effectsLockBlur, value.lock.blur);
      await prefs.setInt(WallpaperPrefsKeys.effectsLockDim, value.lock.dim);
      await prefs.setInt(WallpaperPrefsKeys.effectsLockGrey, value.lock.grey);
      await prefs.setBool(WallpaperPrefsKeys.effectsLink, value.link);
    } catch (error, stack) {
      wallpaperLog.e('failed to persist live wallpaper effects', error, stack);
    }
  }

  Future<void> setHomeEffects(WallpaperEffects value) => setEffects(_effects.copyWith(home: value));

  Future<void> setLockEffects(WallpaperEffects value) => setEffects(_effects.copyWith(lock: value));

  Future<void> setEffectsLink(bool link) => setEffects(_effects.copyWith(link: link));

  Future<void> resetEffects() => setEffects(const WallpaperEffectsConfig());

  Future<void> setGestures(WallpaperGestures value) async {
    _gestures = value;
    _notify();
    try {
      final prefs = await _prefsProvider();
      await prefs.setString(WallpaperPrefsKeys.gesturesDoubleTap, value.doubleTap.name);
      await prefs.setString(WallpaperPrefsKeys.gesturesThreeFinger, value.threeFinger.name);
    } catch (error, stack) {
      wallpaperLog.e('failed to persist live wallpaper gestures', error, stack);
    }
  }

  Future<void> setDoubleTap(WallpaperTapAction action) => setGestures(_gestures.copyWith(doubleTap: action));

  Future<void> setThreeFinger(WallpaperTapAction action) => setGestures(_gestures.copyWith(threeFinger: action));

  Future<void> setAutoAdvance(WallpaperAutoAdvance value) async {
    _autoAdvance = value;
    _notify();
    try {
      final prefs = await _prefsProvider();
      await prefs.setInt(WallpaperPrefsKeys.autoIntervalSeconds, value.interval.seconds);
      await prefs.setString(WallpaperPrefsKeys.autoOrdering, value.ordering.name);
    } catch (error, stack) {
      wallpaperLog.e('failed to persist live wallpaper auto advance', error, stack);
    }
  }

  Future<void> setInterval(WallpaperInterval interval) => setAutoAdvance(_autoAdvance.copyWith(interval: interval));

  Future<void> setOrdering(WallpaperOrdering ordering) => setAutoAdvance(_autoAdvance.copyWith(ordering: ordering));

  Future<void> setLastAdvancedAt(int? millis) async {
    _lastAdvancedAt = millis;
    _notify();
    try {
      final prefs = await _prefsProvider();
      if (millis == null) {
        await prefs.remove(WallpaperPrefsKeys.lastAdvancedAt);
      } else {
        await prefs.setInt(WallpaperPrefsKeys.lastAdvancedAt, millis);
      }
    } catch (error, stack) {
      wallpaperLog.e('failed to persist last advance time', error, stack);
    }
  }

  Future<void> setCurrentIndex(int index) async {
    final clamped = index < 0 ? 0 : index;
    if (clamped == _currentIndex) return;
    _currentIndex = clamped;
    _notify();
    try {
      await (await _prefsProvider()).setInt(WallpaperPrefsKeys.currentIndex, clamped);
    } catch (error, stack) {
      wallpaperLog.e('failed to persist current index', error, stack);
    }
  }

  Future<void> setViewport({double? x, double? y, double? zoom}) async {
    _viewportX = x ?? _viewportX;
    _viewportY = y ?? _viewportY;
    _viewportZoom = _clampZoom(zoom ?? _viewportZoom);
    _notify();
    try {
      final prefs = await _prefsProvider();
      await prefs.setDouble(WallpaperPrefsKeys.viewportX, _viewportX);
      await prefs.setDouble(WallpaperPrefsKeys.viewportY, _viewportY);
      await prefs.setDouble(WallpaperPrefsKeys.viewportZoom, _viewportZoom);
    } catch (error, stack) {
      wallpaperLog.e('failed to persist viewport', error, stack);
    }
  }

  static double _clampZoom(double zoom) => zoom < minViewportZoom ? minViewportZoom : (zoom > maxViewportZoom ? maxViewportZoom : zoom);

  static String? _string(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is String ? value : null;
  }

  static double? _double(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is double ? value : (value is num ? value.toDouble() : null);
  }

  static int? _positiveInt(int? value) => value != null && value > 0 ? value : null;

  static WallpaperEffects _readEffects(SharedPreferences prefs, String side) {
    final home = side == 'home';
    return WallpaperEffects(
      blur: WallpaperEffects.clampBlur(prefs.getInt(home ? WallpaperPrefsKeys.effectsHomeBlur : WallpaperPrefsKeys.effectsLockBlur) ?? WallpaperEffects.defaultBlur),
      dim: WallpaperEffects.clampDim(prefs.getInt(home ? WallpaperPrefsKeys.effectsHomeDim : WallpaperPrefsKeys.effectsLockDim) ?? WallpaperEffects.defaultDim),
      grey: WallpaperEffects.clampGrey(prefs.getInt(home ? WallpaperPrefsKeys.effectsHomeGrey : WallpaperPrefsKeys.effectsLockGrey) ?? WallpaperEffects.defaultGrey),
    );
  }

  static Set<CollectionFilter> _readFilters(SharedPreferences prefs) {
    final filters = <CollectionFilter>{};
    for (final raw in prefs.getStringList(WallpaperPrefsKeys.sourceFilters) ?? const <String>[]) {
      final filter = CollectionFilter.fromJson(raw);
      if (filter != null) filters.add(filter);
    }
    return filters;
  }
}

/// Process-wide live-wallpaper settings, mirroring the app's other singleton
/// preference objects.
final WallpaperPrefs wallpaperPrefs = WallpaperPrefs();
