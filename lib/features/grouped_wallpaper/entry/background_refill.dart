import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_engine.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_command.dart';

/// One headless run of the grouped wallpaper.
///
/// The native service asks the app for a frame when it starts and after a
/// promoted slot, so the same pipeline has to run with no page mounted.
/// `advance` is the auto-advance case (a new photo is due); [command] is a
/// notification action (previous photo, group switch, freeze). Otherwise the run
/// only keeps the saved group's frame ready.
Future<void> groupedWallpaperRefill({required bool advance, String? command}) async {
  final engine = groupedWallpaperEngine;
  try {
    await engine.attach();
    final parsed = GroupedWallpaperCommand.tryParse(command);
    if (parsed != null) {
      await engine.handleCommand(parsed.name);
      groupedWallpaperLog.i('refill.grouped command=${parsed.name}');
      return;
    }
    final result = advance ? await engine.syncNow() : await engine.prepare();
    groupedWallpaperLog.i('refill.grouped done advance=$advance result=${result.name}');
  } catch (error, stack) {
    groupedWallpaperLog.e('refill.grouped failed advance=$advance command=$command', error, stack);
    rethrow;
  }
}
