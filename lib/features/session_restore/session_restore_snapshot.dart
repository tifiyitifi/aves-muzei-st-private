import 'dart:convert';

import 'package:aves/features/session_restore/session_restore_routes.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:flutter/foundation.dart';

/// What to reopen after the app was killed in the background.
///
/// It only carries the top-level page and the filters of its media set. A picker
/// or an external intent is never restored: those belong to a task that no
/// longer exists.
///
/// A page that was pushed over another one (the wallpaper preview, the wallpaper
/// groups) also records that base page: restoring it alone would leave the
/// navigator with nothing to go back to.
///
/// [rangeWallpaper] covers the shared bottom-bar entry, whose two pages live
/// behind one route: the range route is restored either way, and the flag is what
/// brings back the wallpaper page it was showing.
@immutable
class SessionRestoreSnapshot {
  final String routeName;
  final List<String> filtersJson;
  final String? baseRouteName;
  final List<String> baseFiltersJson;
  final bool rangeWallpaper;

  const new({
    required this.routeName,
    this.filtersJson = const [],
    this.baseRouteName,
    this.baseFiltersJson = const [],
    this.rangeWallpaper = false,
  });

  Set<CollectionFilter> get filters => filtersJson.map(CollectionFilter.fromJson).nonNulls.toSet();

  Set<CollectionFilter> get baseFilters => baseFiltersJson.map(CollectionFilter.fromJson).nonNulls.toSet();

  /// Only a page that is normally pushed over another one may carry a base: any
  /// other pair would restore a stack the user never had.
  bool get isValid => restorableSessionRoutes.contains(routeName) && (baseRouteName == null || (pushedRestorableSessionRoutes.contains(routeName) && baseRouteName != routeName && restorableSessionRoutes.contains(baseRouteName)));

  Map<String, Object?> toJsonMap() => {
    'route': routeName,
    if (filtersJson.isNotEmpty) 'filters': filtersJson,
    if (baseRouteName != null) 'baseRoute': baseRouteName,
    if (baseFiltersJson.isNotEmpty) 'baseFilters': baseFiltersJson,
    if (rangeWallpaper) 'rangeWallpaper': true,
  };

  String toJsonString() => jsonEncode(toJsonMap());

  static SessionRestoreSnapshot? tryFromJsonString(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final route = decoded['route'];
      if (route is! String || !restorableSessionRoutes.contains(route)) return null;
      final rawFilters = decoded['filters'];
      final filters = rawFilters is List ? rawFilters.whereType<String>().toList() : <String>[];
      // An unusable base only costs the back target, not the whole snapshot. A
      // base is meaningful under a pushed page only.
      final rawBaseRoute = decoded['baseRoute'];
      final baseRoute = rawBaseRoute is String && pushedRestorableSessionRoutes.contains(route) && rawBaseRoute != route && restorableSessionRoutes.contains(rawBaseRoute) ? rawBaseRoute : null;
      final rawBaseFilters = decoded['baseFilters'];
      final baseFilters = baseRoute != null && rawBaseFilters is List ? rawBaseFilters.whereType<String>().toList() : <String>[];
      // The flag belongs to the shared entry only: with any other route there is
      // no sub-page to bring back, so a stale value is ignored.
      final rangeWallpaper = decoded['rangeWallpaper'] == true && route == VisibleRangePage.routeName;
      return SessionRestoreSnapshot(
        routeName: route,
        filtersJson: filters,
        baseRouteName: baseRoute,
        baseFiltersJson: baseFilters,
        rangeWallpaper: rangeWallpaper,
      );
    } on FormatException {
      // Persisted data may be from an interrupted write; the caller falls back.
      return null;
    }
  }
}
