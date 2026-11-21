import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';

/// The drawer pages this fork owns.
///
/// They are offered after the upstream page options, where the fork's
/// destinations already sit in the bottom-bar editor. All three write wallpaper
/// state, so the drawer leaves them out while a photo is being picked.
const List<String> forkDrawerPageRoutes = [
  VisibleRangePage.routeName,
  MuzeiWallpaperPage.routeName,
  GroupedWallpaperPage.routeName,
];

/// The page options the drawer editor offers: the upstream ones, then the fork's.
///
/// The fork routes are appended instead of added to the upstream option list, so
/// the bottom-bar editor does not offer the same destination twice: it already
/// lists the range and wallpaper pages among its own fork entries.
List<String> drawerPageOptions(List<String> upstreamOptions) => [
  ...upstreamOptions,
  ...forkDrawerPageRoutes.where((route) => !upstreamOptions.contains(route)),
];

/// The entries the drawer renders for an ordered page list.
///
/// Picking a photo already owns the wallpaper state; a fork page opened from the
/// drawer would be a second writer for it, so those entries are dropped instead
/// of greyed. Every other page keeps its place.
List<String> drawerPageEntries(List<String> pages, {required bool picking}) =>
    picking ? pages.where((route) => !forkDrawerPageRoutes.contains(route)).toList() : pages;
