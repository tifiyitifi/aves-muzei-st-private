import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_name.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Localizes a group name.
///
/// A bundled name is stored as `@arbKey`, so it follows the app language and a
/// language change renames it for free. A group the user renamed stores plain
/// text and is shown as-is. A group that has no name yet (just created) falls
/// back to its derived number.
String wallpaperGroupName(BuildContext context, WallpaperGroup group) =>
    wallpaperGroupNameFrom(context.l10n, name: group.name, number: group.number, isNone: group.isNone);

/// Localizes a group name from its stored fields, for the view-only group card
/// filter, which carries the raw name instead of the group row.
String wallpaperGroupNameOf(BuildContext context, {required String name, required int number, bool isNone = false}) =>
    wallpaperGroupNameFrom(context.l10n, name: name, number: number, isNone: isNone);
