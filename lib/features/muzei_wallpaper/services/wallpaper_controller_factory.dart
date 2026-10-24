import 'dart:io';

import 'package:aves/features/muzei_wallpaper/services/wallpaper_baker.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_source_repository.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';

/// Builds the wallpaper controller.
///
/// The foreground page and the headless refill entrypoint are separate Flutter
/// isolates, so they must agree on the wiring; this is the only place that
/// knows it.
abstract final class WallpaperControllerFactory {
  static Future<WallpaperController> create({WallpaperBridge? bridge}) async {
    final platform = bridge ?? WallpaperBridge.instance;
    final root = await platform.stateRoot();
    if (root == null) {
      throw StateError('the live wallpaper platform channel is unavailable');
    }
    final controller = WallpaperController(
      prefs: wallpaperPrefs,
      repository: WallpaperSourceRepository(),
      baker: WallpaperBaker(),
      store: WallpaperStateStore(Directory(root)),
      bridge: platform,
    );
    await controller.init();
    return controller;
  }
}
