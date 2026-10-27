import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Localizes a group name.
///
/// A bundled name is stored as `@arbKey`, so it follows the app language and a
/// language change renames it for free. A group the user renamed stores plain
/// text and is shown as-is. A group that has no name yet (just created) falls
/// back to its derived number.
String wallpaperGroupName(BuildContext context, WallpaperGroup group) =>
    wallpaperGroupNameOf(context, name: group.name, number: group.number, isNone: group.isNone);

/// Localizes a group name from its stored fields, for the view-only group card
/// filter, which carries the raw name instead of the group row.
String wallpaperGroupNameOf(BuildContext context, {required String name, required int number, bool isNone = false}) {
  final l10n = context.l10n;
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
