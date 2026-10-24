import 'package:aves/model/settings/settings.dart';
import 'package:aves_model/aves_model.dart';

/// Whether the live wallpaper keeps a second artwork baked ahead of the
/// current one.
///
/// The flag lives in the app's shared settings (Meta Settings → Advanced), not
/// in `WallpaperPrefs`, so the page, the controller and the headless refill
/// isolate all read the value through the store the user actually edits.
///
/// Only this feature knows what the flag *means*: the settings catalog
/// references [key] and reads through [read], so the queue depth, its disk cost
/// and the cleanup when it is turned off stay inside the wallpaper slice.
abstract final class WallpaperPrefetchSetting {
  /// Baking two artworks ahead keeps the first two taps instant. The extra slot
  /// costs roughly 13 MB of PNGs on a 1080p phone and one more effect rebake
  /// each time an effect changes, so it is a user choice rather than a given.
  static const bool defaultValue = true;

  static const String key = SettingKeys.muzeiWallpaperPrefetchAheadKey;

  /// Reads the value; a headless isolate must initialize the settings engine
  /// first (the refill entrypoint does).
  static bool get enabled => settings.getBool(key) ?? defaultValue;

  /// Catalog reader: the generic settings surface owns the [Settings] instance.
  static bool read(Settings source) => source.getBool(key) ?? defaultValue;
}
