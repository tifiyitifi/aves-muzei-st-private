import 'dart:async';

import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/services/common/channel.dart';
import 'package:flutter/services.dart';

/// What the engine needs from the native grouped wallpaper service.
///
/// The interface exists so the engine can be tested without a platform channel;
/// [GroupedWallpaperBridge] is the production implementation.
abstract interface class GroupedWallpaperPlatform {
  /// Whether [GroupedLiveWallpaperService] is the current system wallpaper.
  Future<bool> isActive();

  /// Absolute directory the renderer and Dart share for `state.json`.
  Future<String?> stateRoot();

  /// Desired wallpaper bitmap size, including the launcher's scrollable width.
  Future<Size?> wallpaperSize();

  /// Asks the renderer to re-read `state.json`.
  Future<void> reload();

  /// Applies the current group's auto-advance interval; `0` turns it off.
  Future<void> scheduleAutoAdvance(int seconds);

  /// Asks the running service to re-post or drop the bar from `state.json`.
  Future<void> refreshNotification();

  /// Opens the system live-wallpaper chooser for this service.
  Future<bool> openChooser();

  /// Registers the native-to-Dart requests: a fresh frame is needed, or the
  /// notification asked for a command (previous photo, group switch, freeze).
  ///
  /// The service asks for a frame when it starts, when the app attaches and after
  /// a tap. The renderer already wrote the promotion to `runtime.json`, so the
  /// signal carries no payload and the engine reads the file itself.
  void setSyncRequestHandler({void Function()? onSyncRequested, void Function(String command)? onCommand});
}

/// Platform contract of the grouped live wallpaper.
///
/// Only lifecycle controls cross the channel: the baked photo and `state.json`
/// stay in Dart, and the renderer reads them directly, so showing a frame never
/// depends on a running Flutter engine.
class GroupedWallpaperBridge implements GroupedWallpaperPlatform {
  static const String channelName = 'deckers.thibault/aves/grouped_wallpaper';

  static const AvesMethodChannel _channel = AvesMethodChannel(channelName);

  static const GroupedWallpaperBridge instance = GroupedWallpaperBridge();

  const new();

  @override
  Future<bool> isActive() async {
    final active = await _invoke<bool>('isActive');
    return active ?? false;
  }

  @override
  Future<String?> stateRoot() => _invoke<String>('stateRoot');

  @override
  Future<Size?> wallpaperSize() async {
    final raw = await _invoke<Map<Object?, Object?>>('wallpaperSize');
    final width = _number(raw?['width']);
    final height = _number(raw?['height']);
    if (width == null || height == null || width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  @override
  Future<void> reload() => _invoke<void>('reload');

  @override
  Future<void> scheduleAutoAdvance(int seconds) => _invoke<void>('scheduleAutoAdvance', {'seconds': seconds});

  @override
  Future<void> refreshNotification() => _invoke<void>('refreshNotification');

  @override
  Future<bool> openChooser() async {
    final opened = await _invoke<bool>('openChooser');
    return opened ?? false;
  }

  @override
  void setSyncRequestHandler({void Function()? onSyncRequested, void Function(String command)? onCommand}) {
    final attached = onSyncRequested != null || onCommand != null;
    unawaited(_invoke<void>('setRequestHandler', {'attached': attached}));
    if (!attached) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'syncRequested':
          onSyncRequested?.call();
        case 'command':
          final arguments = call.arguments;
          final command = arguments is Map ? arguments['command'] : arguments;
          if (command is String) onCommand?.call(command);
      }
      return null;
    });
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // Desktop/test hosts have no live-wallpaper service; the feature stays
      // inert instead of failing every page load.
      return null;
    } on PlatformException catch (error, stack) {
      groupedWallpaperLog.w('platform call $method failed', error, stack);
      return null;
    }
  }

  static double? _number(Object? value) => value is num ? value.toDouble() : null;
}
