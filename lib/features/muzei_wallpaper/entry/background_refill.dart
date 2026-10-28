import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller_factory.dart';

/// Controller reused across the refills served by one warm engine.
///
/// The worker keeps its engine (and therefore this isolate) alive for a short
/// window, so a tap burst does not re-resolve the source and re-read the state
/// for every tap.
WallpaperController? _controller;

/// One headless refill of the Muzei wallpaper.
///
/// A wallpaper tap promotes the prefetched slot natively, so something has to
/// bake the freed slot again even when neither the page nor the app process is
/// alive; auto-advance uses the same run with `advance: true`.
Future<void> muzeiWallpaperRefill({required bool advance}) async {
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
      'refill.muzei done advance=$advance generation=${controller.state.generation} '
      'current=${controller.state.current} next=${controller.state.next} next2=${controller.state.next2}',
    );
  } catch (error, stack) {
    wallpaperLog.e('refill.muzei failed advance=$advance', error, stack);
    rethrow;
  }
}
