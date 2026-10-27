import 'package:aves/l10n/l10n.dart';

/// Localizes a group name from its stored fields.
///
/// Kept free of [BuildContext] so the wallpaper engine can resolve the name it
/// writes into `state.json`; the page's helper delegates here, so the bundled
/// names are spelled one way for both.
String wallpaperGroupNameFrom(AppLocalizations l10n, {required String name, required int number, bool isNone = false}) {
  if (name.startsWith('@')) {
    return switch (name.substring(1)) {
      'wallpaperGroupNone' => l10n.wallpaperGroupNone,
      'wallpaperGroupDefaultAll' => l10n.wallpaperGroupDefaultAll,
      'wallpaperGroupDefaultDcim' => l10n.wallpaperGroupDefaultDcim,
      'wallpaperGroupDefaultPictures' => l10n.wallpaperGroupDefaultPictures,
      // An unknown key is a data error, but showing it beats an empty chip.
      final key => key,
    };
  }
  if (name.isNotEmpty) return name;
  return isNone ? l10n.wallpaperGroupNone : l10n.wallpaperGroupFallbackName(number);
}
