import 'package:aves/model/settings/settings.dart';
import 'package:aves_model/aves_model.dart';

/// Whether deleting the copied single artwork asks for confirmation first.
///
/// Deleting the copy is what stops a single source whose original is already
/// gone, so it confirms by default. The dialog also offers "don't ask again",
/// and this flag is what that checkbox turns off; the user can turn it back on
/// in Meta Settings → Advanced.
abstract final class WallpaperSourceDeleteSetting {
  static const bool defaultValue = true;

  static const String key = SettingKeys.muzeiWallpaperSourceDeleteConfirmKey;

  static bool get enabled => settings.getBool(key) ?? defaultValue;

  static bool read(Settings source) => source.getBool(key) ?? defaultValue;

  static void setEnabled(bool value) => settings.set(key, value);
}

/// Whether deleting a photo opened from the wallpaper viewer asks first.
///
/// The viewer normally deletes without this question; here it can be reached
/// from the wallpaper page, where deleting the original or the private copy
/// changes what the wallpaper can show next.
abstract final class WallpaperViewerDeleteSetting {
  static const bool defaultValue = true;

  static const String key = SettingKeys.muzeiWallpaperViewerDeleteConfirmKey;

  static bool get enabled => settings.getBool(key) ?? defaultValue;

  static bool read(Settings source) => source.getBool(key) ?? defaultValue;

  static void setEnabled(bool value) => settings.set(key, value);
}
