import 'dart:async';

import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/channel.dart';
import 'package:flutter/services.dart';

/// A frame the platform decoded, covered and wrote to disk.
///
/// Only the size and a darkness sample come back: the pixels never cross the
/// channel, so a bake costs one file write instead of a 30 MB round trip.
class GroupedFrameWriteResult {
  final int width;
  final int height;

  /// `64 × 64` RGBA pixels of the baked frame.
  final Uint8List thumbnail;

  const new({required this.width, required this.height, required this.thumbnail});
}

/// What the engine needs from the native grouped wallpaper service.
///
/// The interface exists so the engine can be tested without a platform channel;
/// [GroupedWallpaperBridge] is the production implementation.
abstract interface class GroupedWallpaperPlatform {
  /// Whether [GroupedLiveWallpaperService] is the current system wallpaper.
  Future<bool> isActive();

  /// Whether the wallpaper was in use and the system dropped it.
  ///
  /// The platform owns this decision: the OEM's fallback and a wallpaper the
  /// user picked both look like "not ours", and only the baked state plus the
  /// wallpaper file tell them apart.
  Future<bool> restoreOffer();

  /// Absolute directory the renderer and Dart share for `state.json`.
  Future<String?> stateRoot();

  /// Desired wallpaper bitmap size, including the launcher's scrollable width.
  Future<Size?> wallpaperSize();

  /// Fraction of the scroll range one home page takes, from the launcher.
  ///
  /// `0` means the launcher never pans the wallpaper (a single-page home
  /// screen); `null` means no offset callback has arrived yet, so the caller
  /// follows the user's switch instead of guessing.
  Future<double?> scrollStep();

  /// The slot the real wallpaper engine is drawing, plus the surface it draws.
  ///
  /// `state.json` records what was last baked, but the renderer can promote a
  /// slot on its own and a reload keeps drawing the slot it had, so the two can
  /// disagree. Only the engine knows which frame is on screen, and `lock` tells
  /// whether that frame is the lock effect image. Returns null when no engine is
  /// running.
  Future<({int slot, bool lock})?> displayedSlot();

  /// Asks the renderer to re-read `state.json`.
  Future<void> reload();

  /// Applies the current group's auto-advance interval; `0` turns it off.
  Future<void> scheduleAutoAdvance(int seconds);

  /// Restarts the interval from now, replacing any pending run.
  ///
  /// Used after an explicit previous/next step: the countdown starts over from
  /// the photo the user chose instead of firing right after it.
  Future<void> restartAutoAdvance(int seconds);

  /// Asks the running service to re-post or drop the bar from `state.json`.
  Future<void> refreshNotification();

  /// Drops a bar the service left behind when it was killed without cleanup.
  ///
  /// The app calls it when it attaches the engine and finds this service is no
  /// longer the system wallpaper, so a bar the system never got to remove does
  /// not survive until the next boot.
  Future<void> cancelNotification();

  /// Opens the system live-wallpaper chooser for this service.
  Future<bool> openChooser();

  /// Decodes [entry], covers it to [targetSize] and writes the frame to
  /// [photoPath], which must be inside the state root.
  ///
  /// Returns null when the platform cannot bake this entry (no service, an
  /// undecodable format, a failing channel); the caller then falls back to the
  /// Dart baker instead of failing the bake.
  Future<GroupedFrameWriteResult?> writeFrame({
    required AvesEntry entry,
    required Size targetSize,
    required String photoPath,
    required int quality,
  });

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
  Future<bool> restoreOffer() async {
    final offered = await _invoke<bool>('restoreOffer');
    return offered ?? false;
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
  Future<double?> scrollStep() async {
    final step = await _invoke<double>('scrollStep');
    if (step == null || step < 0) return null;
    return step;
  }

  @override
  Future<({int slot, bool lock})?> displayedSlot() async {
    final raw = await _invoke<Map<Object?, Object?>>('displayedSlot');
    final slot = _number(raw?['slot']);
    if (slot == null || slot < 0) return null;
    return (slot: slot.toInt(), lock: raw?['lock'] == true);
  }

  @override
  Future<void> reload() => _invoke<void>('reload');

  @override
  Future<void> scheduleAutoAdvance(int seconds) => _invoke<void>('scheduleAutoAdvance', {'seconds': seconds});

  @override
  Future<void> restartAutoAdvance(int seconds) => _invoke<void>('restartAutoAdvance', {'seconds': seconds});

  @override
  Future<void> refreshNotification() => _invoke<void>('refreshNotification');

  @override
  Future<void> cancelNotification() => _invoke<void>('cancelNotification');

  @override
  Future<bool> openChooser() async {
    final opened = await _invoke<bool>('openChooser');
    return opened ?? false;
  }

  @override
  Future<GroupedFrameWriteResult?> writeFrame({
    required AvesEntry entry,
    required Size targetSize,
    required String photoPath,
    required int quality,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>('writeFrame', {
      'uri': entry.uri,
      'mimeType': entry.mimeType,
      'pageId': entry.pageId,
      'sizeBytes': entry.sizeBytes,
      'rotationDegrees': entry.rotationDegrees,
      'isFlipped': entry.isFlipped,
      'targetWidth': targetSize.width.round(),
      'targetHeight': targetSize.height.round(),
      'outputPath': photoPath,
      'quality': quality,
    });
    if (raw == null) return null;
    final width = raw['width'];
    final height = raw['height'];
    final thumbnail = raw['thumbnail'];
    if (width is! int || height is! int || width <= 0 || height <= 0) return null;
    if (thumbnail is! Uint8List || thumbnail.isEmpty) return null;
    return GroupedFrameWriteResult(width: width, height: height, thumbnail: thumbnail);
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
