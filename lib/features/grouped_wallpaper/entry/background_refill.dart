import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_engine.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';

/// One headless run of the grouped wallpaper.
///
/// The native service asks the app for a frame when it starts and after a
/// promoted slot, so the same pipeline has to run with no page mounted.
/// `advance` is the auto-advance case (a new photo is due); otherwise the run
/// only keeps the saved group's frame ready.
Future<void> groupedWallpaperRefill({required bool advance}) async {
  final engine = groupedWallpaperEngine;
  try {
    await engine.attach();
    final result = advance ? await engine.syncNow() : await engine.prepare();
    groupedWallpaperLog.i('refill.grouped done advance=$advance result=${result.name}');
  } catch (error, stack) {
    groupedWallpaperLog.e('refill.grouped failed advance=$advance', error, stack);
    rethrow;
  }
}
