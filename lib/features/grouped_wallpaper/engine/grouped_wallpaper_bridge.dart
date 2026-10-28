import 'dart:async';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/services/common/channel.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A slot the renderer promoted on its own, told to the app over the channel.
///
/// The renderer also records it in `runtime.json`, but that write is
/// asynchronous and a running app can bake before it lands. The channel message
/// is delivered after the promotion, so the app adopts it without racing the
/// file; the file stays the fallback for the background worker, which has no
/// channel.
@immutable
class GroupedWallpaperPromotion extends Equatable {
  final int generation;
  final int current;
  final int next;

  const new({
    required this.generation,
    required this.current,
    required this.next,
  });

  static GroupedWallpaperPromotion? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final generation = _int(raw['generation']);
    final current = _int(raw['current']);
    if (generation == null || current == null || current < 0) return null;
    return GroupedWallpaperPromotion(
      generation: generation,
      current: current,
      next: _int(raw['next']) ?? -1,
    );
  }

  static int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  /// The same promotion as the runtime record the renderer writes.
  GroupedWallpaperRuntime toRuntime() => GroupedWallpaperRuntime(
        generation: generation,
        current: current,
        next: next,
        refillRequested: true,
      );

  @override
  List<Object?> get props => [generation, current, next];
}

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

  /// Opens the system live-wallpaper chooser for this service.
  Future<bool> openChooser();

  /// Registers the native-to-Dart request that a fresh frame is needed.
  ///
  /// The service asks for it when it starts, when the app attaches and after a
  /// tap. [onSyncRequested] receives the slot the renderer promoted, or null for
  /// a plain request.
  void setSyncRequestHandler({void Function(GroupedWallpaperPromotion? promotion)? onSyncRequested});
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
  Future<bool> openChooser() async {
    final opened = await _invoke<bool>('openChooser');
    return opened ?? false;
  }

  @override
  void setSyncRequestHandler({void Function(GroupedWallpaperPromotion? promotion)? onSyncRequested}) {
    final attached = onSyncRequested != null;
    unawaited(_invoke<void>('setRequestHandler', {'attached': attached}));
    if (!attached) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'syncRequested') {
        onSyncRequested.call(GroupedWallpaperPromotion.tryParse(call.arguments));
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
