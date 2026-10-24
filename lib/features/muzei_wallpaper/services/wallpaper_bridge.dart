import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/services/common/channel.dart';
import 'package:flutter/services.dart';

/// Platform contract of the live-wallpaper feature.
///
/// The native side owns the wallpaper service and only exposes lifecycle
/// controls here. Baked files and `state.json` stay in Dart; the renderer reads
/// them directly so a background change does not depend on this channel.
class WallpaperBridge {
  static const String channelName = 'deckers.thibault/aves/muzei_wallpaper';

  static const AvesMethodChannel _channel = AvesMethodChannel(channelName);

  static const WallpaperBridge instance = WallpaperBridge();

  const new();

  /// Whether [AvesLiveWallpaperService] is the current system wallpaper.
  Future<bool> isActive() async {
    final active = await _invoke<bool>('isActive');
    return active ?? false;
  }

  /// Asks the renderer to re-read `state.json` and show its current slot.
  Future<void> reload() => _invoke<void>('reload');

  /// Opens the system live-wallpaper chooser for this service.
  ///
  /// Returns whether a picker activity was launched, so the page can explain an
  /// OEM that blocks both intents instead of failing silently.
  Future<bool> openChooser() async {
    final opened = await _invoke<bool>('openChooser');
    return opened ?? false;
  }

  /// Desired wallpaper bitmap size, including the launcher's scrollable width.
  Future<Size?> wallpaperSize() async {
    final raw = await _invoke<Map<Object?, Object?>>('wallpaperSize');
    final width = _number(raw?['width']);
    final height = _number(raw?['height']);
    if (width == null || height == null || width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  /// Absolute path the renderer and Dart share for `state.json` and slots.
  Future<String?> stateRoot() => _invoke<String>('stateRoot');

  /// Registers native-to-Dart requests.
  ///
  /// A wallpaper tap promotes the prefetched slot natively, so the renderer asks
  /// the running app (`advanceRequested`) to adopt it and bake the freed slot
  /// again; `reloadRequested` refreshes the preview after the service changed
  /// slots. Without a running app the runtime stays marked for refill and the
  /// next app start adopts it.
  void setRequestHandler({
    VoidCallback? onAdvanceRequested,
    VoidCallback? onReloadRequested,
  }) {
    if (onAdvanceRequested == null && onReloadRequested == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'advanceRequested':
          onAdvanceRequested?.call();
        case 'reloadRequested':
          onReloadRequested?.call();
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
      wallpaperLog.w('platform call $method failed', error, stack);
      return null;
    }
  }

  static double? _number(Object? value) => value is num ? value.toDouble() : null;
}
