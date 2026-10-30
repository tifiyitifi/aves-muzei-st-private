import 'dart:convert';

import 'package:aves/features/collection_paging/lens/scope_registry.dart';
import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/widgets/about/about_page.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/search/page.dart';
import 'package:aves/widgets/debug/app_debug_page.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/countries_page.dart';
import 'package:aves/widgets/filter_grids/places_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves/widgets/home/home_page.dart';
import 'package:aves/widgets/navigation/drawer/tile.dart';
import 'package:aves/widgets/navigation/nav_display.dart';
import 'package:aves/widgets/search/collection_search_page_route.dart';
import 'package:aves/widgets/settings/settings_page.dart';
import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class AvesNavItem extends Equatable {
  final String route;
  final Set<CollectionFilter>? filters;
  final String? path;

  @override
  List<Object?> get props => [route, filters, path];

  const new({
    required this.route,
    this.filters,
    this.path,
  });

  Widget getIcon(BuildContext context) {
    if (route == CollectionPage.routeName) {
      return DrawerFilterIcon(filter: filters?.firstOrNull);
    }

    final textScaler = MediaQuery.textScalerOf(context);
    final iconSize = textScaler.scale(24);
    return Icon(NavigationDisplay.getPageIcon(route), size: iconSize);
  }

  String getText(BuildContext context) {
    if (route == CollectionPage.routeName) {
      return NavigationDisplay.getFilterTitle(context, filters?.firstOrNull);
    }
    return NavigationDisplay.getPageTitle(context, route);
  }

  /// The filters this destination opens.
  ///
  /// A collection destination that declares none is the media-set slot: it
  /// reopens the view the slot last showed (an album opened from the albums page,
  /// a search) instead of resetting the library behind the user's back. A
  /// destination that names its filters (video, favourites, a pinned album)
  /// always opens exactly them.
  Set<CollectionFilter>? get effectiveFilters {
    final declared = filters;
    if (route != CollectionPage.routeName) return declared;
    if (declared != null && declared.isNotEmpty) return declared;
    return mediaSetTab.filters ?? declared;
  }

  Future<void> goTo(BuildContext context, {bool? topLevel}) async {
    topLevel ??= _defaultTopLevel;
    // A borrowed view (the wallpaper picker) owns its media set: following the
    // app-wide slot would leave the task it was opened for.
    final hookFilters = this.route == CollectionPage.routeName ? CollectionViewHooksScope.read(context)?.mediaSetFilters : null;
    final targetFilters = hookFilters ?? effectiveFilters;
    if (this.route == CollectionPage.routeName) {
      // A tap on a collection item is the decision to show it: resolve it while
      // the route transition runs, so its page opens on a published window.
      scopeRegistry.prewarm(source: context.read<CollectionSource>(), filters: targetFilters);
    }
    final route = routeBuilder(context, topLevel: topLevel, collectionFilters: targetFilters);
    if (topLevel) {
      await Navigator.maybeOf(context)?.pushAndRemoveUntil(
        route,
        (route) => false,
      );
    } else {
      await Navigator.maybeOf(context)?.push(route);
    }
  }

  bool get _defaultTopLevel {
    switch (route) {
      case AboutPage.routeName:
      case AppDebugPage.routeName:
      case MuzeiWallpaperPage.routeName:
      case GroupedWallpaperPage.routeName:
      case VisibleRangePage.routeName:
      case SearchPage.routeName:
      case SettingsPage.routeName:
        return false;
      default:
        return true;
    }
  }

  Route routeBuilder(BuildContext context, {required bool topLevel, Set<CollectionFilter?>? collectionFilters}) {
    switch (route) {
      case HomePage.routeName:
        return settings.homeNavItem.routeBuilder(context, topLevel: topLevel);
      case SearchPage.routeName:
        final currentCollection = context.read<CollectionLens?>();
        return CollectionSearchPageRoute(
          context: context,
          parentCollection: topLevel ? currentCollection?.copyWith() : currentCollection,
        );
      default:
        return MaterialPageRoute(
          settings: RouteSettings(name: route),
          builder: _materialPageBuilder(route, collectionFilters),
        );
    }
  }

  WidgetBuilder _materialPageBuilder(String route, Set<CollectionFilter?>? collectionFilters) {
    switch (route) {
      case CollectionPage.routeName:
        final targetFilters = collectionFilters ?? filters;
        return (context) => CollectionPage(
          source: context.read<CollectionSource>(),
          filters: targetFilters,
        );
      case AlbumListPage.routeName:
        return (_) => const AlbumListPage(initialGroup: null);
      case CountryListPage.routeName:
        return (_) => const CountryListPage();
      case PlaceListPage.routeName:
        return (_) => const PlaceListPage();
      case TagListPage.routeName:
        return (_) => const TagListPage(initialGroup: null);
      case AboutPage.routeName:
        return (_) => const AboutPage();
      case AppDebugPage.routeName:
        return (_) => const AppDebugPage();
      case ExplorerPage.routeName:
        return (_) => ExplorerPage(path: path);
      case MuzeiWallpaperPage.routeName:
        return (_) => const MuzeiWallpaperPage();
      case GroupedWallpaperPage.routeName:
        // The bottom bar's own entry. It keeps the group the user was last on,
        // unlike the cold-start route, which has to describe the playing one.
        return (_) => const GroupedWallpaperPage();
      case VisibleRangePage.routeName:
        return (_) => const VisibleRangeShellPage();
      case SettingsPage.routeName:
        return (_) => const SettingsPage();
      default:
        throw Exception('unknown route=$route');
    }
  }

  // serialization

  static AvesNavItem _fromMap(Map<String, Object?> json) {
    return AvesNavItem(
      route: json['route'] as String,
      filters: (json['filters'] as List?)?.map(CollectionFilter.fromJson).nonNulls.toSet(),
      path: json['path'] as String?,
    );
  }

  Map<String, Object?> _toMap() => {
    'route': route,
    if (filters != null) 'filters': filters!.map((v) => v.toJsonMap()).toList(),
    'path': ?path,
  };

  String toJson() => jsonEncode(_toMap());

  static AvesNavItem? fromJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;

    try {
      final jsonMap = jsonDecode(jsonString);
      if (jsonMap is Map<String, Object?>) {
        return _fromMap(jsonMap);
      }
      debugPrint('failed to parse navigation item from json=$jsonString');
    } catch (error) {
      // no need for stack
      debugPrint('failed to parse navigation item from json=$jsonString error=$error');
    }
    return null;
  }
}
