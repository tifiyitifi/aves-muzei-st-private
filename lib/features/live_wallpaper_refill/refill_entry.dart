import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/entry/background_refill.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/live_wallpaper_refill/log.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/muzei_wallpaper/entry/background_refill.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/model/device.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Channel between the background worker and the shared refill entrypoint.
///
/// The worker owns the Flutter engine; this isolate only answers `refill` and
/// reports when it can be invoked, so the worker never talks to a half-started
/// isolate.
const String liveWallpaperRefillChannelName = 'deckers.thibault/aves/live_wallpaper_refill';

/// Target ids, mirroring `LiveWallpaperTarget` on the native side.
const String liveWallpaperTargetMuzei = 'muzei';
const String liveWallpaperTargetGrouped = 'grouped';

/// One headless refill of one live wallpaper.
///
/// [command] is the notification's request (`previousArtwork`, `nextGroup`,
/// ...), already resolved by the target; a plain tap or interval leaves it null.
typedef LiveWallpaperRefill = Future<void> Function({required bool advance, String? command});

/// The wallpapers this entrypoint can serve.
///
/// The map is the only place that knows both features; each one keeps its own
/// baking, state files and renderer.
const Map<String, LiveWallpaperRefill> _refills = {
  liveWallpaperTargetMuzei: muzeiWallpaperRefill,
  liveWallpaperTargetGrouped: groupedWallpaperRefill,
};

/// Resolves the refill for [target].
///
/// The dispatch is the only part of the isolate that can be exercised without
/// starting a Flutter engine, so it is exposed for the host test.
@visibleForTesting
LiveWallpaperRefill resolveLiveWallpaperRefill(Object? target, {Map<String, LiveWallpaperRefill>? refills}) {
  final refill = (refills ?? _refills)[target];
  if (refill == null) throw ArgumentError.value(target, 'target', 'unknown live wallpaper');
  return refill;
}

/// Handles one `refill` call from the native worker.
///
/// `advance` is a strict boolean: any other value means "do not advance", which
/// keeps a malformed call from silently changing the wallpaper.
@visibleForTesting
Future<bool> handleLiveWallpaperRefillCall(Object? arguments, {Map<String, LiveWallpaperRefill>? refills}) async {
  if (arguments is! Map) throw ArgumentError.value(arguments, 'arguments', 'expected a map');
  final refill = resolveLiveWallpaperRefill(arguments['target'], refills: refills);
  final command = arguments['command'];
  await refill(advance: arguments['advance'] == true, command: command is String ? command : null);
  return true;
}

const AvesMethodChannel _channel = AvesMethodChannel(liveWallpaperRefillChannelName);

/// Headless entrypoint shared by both live wallpapers.
///
/// A tap or an interval can change the wallpaper while neither the page nor the
/// app process is alive, so the native worker starts this isolate through a
/// callback handle registered by [registerLiveWallpaperRefillCallback], runs one
/// refill, and destroys the engine.
///
/// Keeping the bake in Dart is deliberate: sources, EXIF decoding and the effect
/// pipelines already live here, and a second Kotlin renderer would drift from the
/// preview.
@pragma('vm:entry-point')
Future<void> liveWallpaperRefillMain() async {
  // This isolate has its own `Log` state: without this, every feature channel
  // is closed here and a failed background refill leaves no trace at all.
  Log.init(debugChannels: [...groupedWallpaperDebugLogKeys, ...liveWallpaperRefillDebugLogKeys]);
  WidgetsFlutterBinding.ensureInitialized();
  liveWallpaperRefillLog.i('refill.entry start');

  try {
    initPlatformServices();
    await androidFileUtils.init();
    await localMediaDb.init();
    await device.init();
    await vaults.init();
    await settings.init(monitorPlatformSettings: false, shouldSanitize: false);
    // A lock sent from the notification is handled here too: the worker has no
    // page, so the lock service has to be loaded before the command runs.
    await wallpaperLockService.init();
  } catch (error, stack) {
    liveWallpaperRefillLog.e('refill.entry failed to initialize services', error, stack);
    rethrow;
  }

  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'refill':
        return handleLiveWallpaperRefillCall(call.arguments);
      default:
        throw MissingPluginException('unsupported refill method ${call.method}');
    }
  });

  // The worker waits for this before invoking `refill`, so the handler is
  // registered before the first call can arrive.
  await _channel.invokeMethod<void>('initialized');
  liveWallpaperRefillLog.i('refill.entry ready');
}

/// Registers [liveWallpaperRefillMain] with the native worker.
///
/// Called at every app start, because the handle is part of the AOT snapshot and
/// changes with each build. The handle survives process death, so a tap on the
/// wallpaper can refill even days after the app was last opened.
Future<void> registerLiveWallpaperRefillCallback() async {
  final handle = ui.PluginUtilities.getCallbackHandle(liveWallpaperRefillMain)?.toRawHandle();
  if (handle == null) {
    liveWallpaperRefillLog.w('refill.entry has no callback handle');
    return;
  }
  try {
    await _channel.invokeMethod<void>('registerCallback', {'callbackHandle': handle});
  } on MissingPluginException {
    // Desktop/test hosts have no background pipeline.
  }
}
