import 'dart:ui' as ui;

import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller_factory.dart';
import 'package:aves/model/device.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Channel between the background worker and the headless refill entrypoint.
///
/// The worker owns the Flutter engine; this isolate only answers `refill` and
/// reports when it can be invoked, so the worker never talks to a half-started
/// isolate.
const String wallpaperRefillChannelName = 'deckers.thibault/aves/muzei_wallpaper_background';

const AvesMethodChannel _channel = AvesMethodChannel(wallpaperRefillChannelName);

/// Controller reused across the refills served by one warm engine.
///
/// The worker keeps its engine (and therefore this isolate) alive for a short
/// window, so a tap burst does not re-resolve the source and re-read the state
/// for every tap.
WallpaperController? _controller;

/// Headless entrypoint: tops up the baked slots without the app UI.
///
/// A wallpaper tap promotes the prefetched slot natively, so something has to
/// bake the freed slot again even when neither the page nor the app process is
/// alive. The native `WallpaperRefillWorker` starts this isolate through a
/// callback handle registered by [registerWallpaperRefillCallback], runs one
/// refill, and destroys the engine. Auto-advance uses the same run with
/// `advance: true`.
///
/// Keeping the bake in Dart is deliberate: sources, EXIF decoding and the blur
/// pipeline already live here, and a second Kotlin renderer would drift from the
/// preview.
@pragma('vm:entry-point')
Future<void> wallpaperRefillMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  wallpaperLog.i('refill.entry start');

  try {
    initPlatformServices();
    await androidFileUtils.init();
    await localMediaDb.init();
    await device.init();
    await vaults.init();
    await settings.init(monitorPlatformSettings: false, shouldSanitize: false);
  } catch (error, stack) {
    wallpaperLog.e('refill.entry failed to initialize services', error, stack);
    rethrow;
  }

  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'refill':
        final arguments = call.arguments;
        final advance = arguments is Map && arguments['advance'] == true;
        await _refill(advance: advance);
        return true;
      default:
        throw MissingPluginException('unsupported refill method ${call.method}');
    }
  });

  // The worker waits for this before invoking `refill`, so the handler is
  // registered before the first call can arrive.
  await _channel.invokeMethod<void>('initialized');
  wallpaperLog.i('refill.entry ready');
}

/// Registers [wallpaperRefillMain] with the native worker.
///
/// Called from the foreground page; the handle survives process death, so a tap
/// on the wallpaper can refill even days after the app was last opened.
Future<void> registerWallpaperRefillCallback() async {
  final handle = ui.PluginUtilities.getCallbackHandle(wallpaperRefillMain)?.toRawHandle();
  if (handle == null) {
    wallpaperLog.w('refill.entry has no callback handle');
    return;
  }
  await WallpaperBridge.instance.registerRefillCallback(handle);
}

Future<void> _refill({required bool advance}) async {
  WallpaperController? controller;
  try {
    // Kept for the engine's lifetime: the worker reuses a warm engine across a
    // tap burst, and re-initializing the source every time would add a database
    // count to each refill.
    controller = _controller ??= await WallpaperControllerFactory.create();
    if (advance) {
      // Auto-advance: promote the prefetched slot, bake the freed one, and let
      // the native scheduler start the next countdown.
      if (controller.next == null) await controller.prefetch();
      if (controller.next != null) await controller.advance();
    } else {
      // A wallpaper tap already promoted the slot natively; adopt it so the
      // next artwork is baked into the slot it left behind.
      await controller.syncRuntime();
    }
    await controller.idle;
    wallpaperLog.i(
      'refill.entry done advance=$advance generation=${controller.state.generation} '
      'current=${controller.state.current} next=${controller.state.next} next2=${controller.state.next2}',
    );
  } catch (error, stack) {
    wallpaperLog.e('refill.entry failed advance=$advance', error, stack);
    rethrow;
  }
}
