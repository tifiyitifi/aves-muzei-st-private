import 'dart:convert';

import 'package:aves/features/session_restore/session_restore_routes.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:flutter/foundation.dart';

/// What to reopen after the app was killed in the background.
///
/// It only carries the top-level page and the filters of its media set. A picker
/// or an external intent is never restored: those belong to a task that no
/// longer exists.
///
/// A page that was pushed over another one (the wallpaper preview) also records
/// that base page: restoring it alone would leave the navigator with nothing to
/// go back to.
@immutable
class SessionRestoreSnapshot {
  final String routeName;
  final List<String> filtersJson;
  final String? baseRouteName;
  final List<String> baseFiltersJson;

  const new({
    required this.routeName,
    this.filtersJson = const [],
    this.baseRouteName,
    this.baseFiltersJson = const [],
  });

  Set<CollectionFilter> get filters => filtersJson.map(CollectionFilter.fromJson).nonNulls.toSet();

  Set<CollectionFilter> get baseFilters => baseFiltersJson.map(CollectionFilter.fromJson).nonNulls.toSet();

  /// The pages to rebuild, bottom first.
  List<String> get routeStack => [?baseRouteName, routeName];

  bool get isValid => restorableSessionRoutes.contains(routeName) && (baseRouteName == null || (baseRouteName != routeName && restorableSessionRoutes.contains(baseRouteName)));

  Map<String, Object?> toJsonMap() => {
    'route': routeName,
    if (filtersJson.isNotEmpty) 'filters': filtersJson,
    if (baseRouteName != null) 'baseRoute': baseRouteName,
    if (baseFiltersJson.isNotEmpty) 'baseFilters': baseFiltersJson,
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
      // An unusable base only costs the back target, not the whole snapshot.
      final rawBaseRoute = decoded['baseRoute'];
      final baseRoute = rawBaseRoute is String && rawBaseRoute != route && restorableSessionRoutes.contains(rawBaseRoute) ? rawBaseRoute : null;
      final rawBaseFilters = decoded['baseFilters'];
      final baseFilters = baseRoute != null && rawBaseFilters is List ? rawBaseFilters.whereType<String>().toList() : <String>[];
      return SessionRestoreSnapshot(
        routeName: route,
        filtersJson: filters,
        baseRouteName: baseRoute,
        baseFiltersJson: baseFilters,
      );
    } on FormatException {
      // Persisted data may be from an interrupted write; the caller falls back.
      return null;
    }
  }
}
