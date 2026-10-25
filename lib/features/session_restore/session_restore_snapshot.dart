import 'dart:convert';

import 'package:aves/features/session_restore/session_restore_routes.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:flutter/foundation.dart';

/// What to reopen after the app was killed in the background.
///
/// It only carries the top-level page and the filters of its media set. A picker
/// or an external intent is never restored: those belong to a task that no
/// longer exists.
@immutable
class SessionRestoreSnapshot {
  final String routeName;
  final List<String> filtersJson;

  const new({
    required this.routeName,
    this.filtersJson = const [],
  });

  Set<CollectionFilter> get filters => filtersJson.map(CollectionFilter.fromJson).nonNulls.toSet();

  bool get isValid => restorableSessionRoutes.contains(routeName);

  Map<String, Object?> toJsonMap() => {
    'route': routeName,
    if (filtersJson.isNotEmpty) 'filters': filtersJson,
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
      return SessionRestoreSnapshot(routeName: route, filtersJson: filters);
    } on FormatException {
      // Persisted data may be from an interrupted write; the caller falls back.
      return null;
    }
  }
}
