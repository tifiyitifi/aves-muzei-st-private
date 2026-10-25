import 'package:aves/model/settings/settings.dart';
import 'package:aves_model/aves_model.dart';

/// Whether resetting the photo source asks for confirmation first.
///
/// Resetting drops every filter the user built for the wallpaper, so the action
/// confirms by default; the dialog also offers "don't ask again", and this flag
/// is what that checkbox turns off. It lives in the app's shared settings (Meta
/// Settings → Advanced) rather than in `WallpaperPrefs`, so the page and the
/// settings surface read the same value through the store the user edits.
///
/// Only this feature knows what the flag means: the catalog references [key] and
/// reads through [read], so the dialog and its wording stay inside the wallpaper
/// slice.
abstract final class WallpaperSourceResetSetting {
  /// Confirming by default protects the filter set the user may have spent a
  /// while building; a user who resets often can turn the question off.
  static const bool defaultValue = true;

  static const String key = SettingKeys.muzeiWallpaperSourceResetConfirmKey;

  /// Reads the value from the current settings store.
  static bool get enabled => settings.getBool(key) ?? defaultValue;

  /// Catalog reader: the generic settings surface owns the [Settings] instance.
  static bool read(Settings source) => source.getBool(key) ?? defaultValue;

  /// Remembers "don't ask again" from the dialog.
  static void setEnabled(bool value) => settings.set(key, value);
}
