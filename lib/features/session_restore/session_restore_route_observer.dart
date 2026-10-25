import 'package:aves/features/session_restore/session_restore_routes.dart';
import 'package:flutter/widgets.dart';

/// Tracks which restorable page is on top of the app's navigator.
///
/// Only the root navigator is observed. The wallpaper picker has its own nested
/// navigator, so its pages never become the page the app restores.
class SessionRestoreRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// The topmost page that [restorableSessionRoutes] accepts, if any.
  String? get currentRestorableRoute {
    final index = _topRestorableIndex;
    return index < 0 ? null : _stack[index].settings.name;
  }

  /// The page the current restorable route was pushed over, when that route is
  /// one of [pushedRestorableSessionRoutes] (the wallpaper preview).
  String? get currentRestorableBaseRoute {
    final index = _topRestorableIndex;
    if (index < 0) return null;
    if (!pushedRestorableSessionRoutes.contains(_stack[index].settings.name)) return null;
    for (var i = index - 1; i >= 0; i--) {
      final name = _stack[i].settings.name;
      if (name != null && restorableSessionRoutes.contains(name)) return name;
    }
    return null;
  }

  int get _topRestorableIndex {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final name = _stack[i].settings.name;
      if (name != null && restorableSessionRoutes.contains(name)) return i;
    }
    return -1;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
      if (index >= 0) {
        _stack[index] = newRoute;
      } else {
        _stack.add(newRoute);
      }
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final SessionRestoreRouteObserver sessionRestoreRouteObserver = SessionRestoreRouteObserver();
