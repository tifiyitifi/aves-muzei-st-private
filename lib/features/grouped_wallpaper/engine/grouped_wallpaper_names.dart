import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_name.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/settings/settings.dart';

/// Resolves a group's stored name to display text.
typedef GroupedWallpaperNameResolver = String Function(WallpaperGroup group);

/// Localizes a group name without a [BuildContext].
///
/// The engine writes the resolved text into `state.json`, because the native
/// renderer and the notification read that file and have no ARB access. A
/// bundled name is stored as `@arbKey` and follows the app language; a renamed
/// group stores plain text.
String resolveGroupedWallpaperName(WallpaperGroup group) {
  final l10n = lookupAppLocalizations(settings.resolvedLocale);
  return wallpaperGroupNameFrom(l10n, name: group.name, number: group.number, isNone: group.isNone);
}
