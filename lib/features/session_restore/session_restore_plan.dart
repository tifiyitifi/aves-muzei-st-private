import 'package:aves/features/session_restore/session_restore_routes.dart';
import 'package:aves/features/session_restore/session_restore_snapshot.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/widgets/collection/collection_page.dart';

/// What a cold start rebuilds from a saved snapshot.
///
/// `filters` and `baseFilters` stay null for any page but the collection: only a
/// media set carries filters, and a null override keeps the configured home
/// collection for a page that was never browsing its own.
///
/// `rangeWallpaper` is set when the shared bottom-bar entry was showing the
/// wallpaper page: the route is the range one either way, so the flag is what
/// reopens the right sub-page.
typedef SessionRestorePlan = ({
  String routeName,
  Set<CollectionFilter>? filters,
  String? baseRouteName,
  Set<CollectionFilter>? baseFilters,
  bool rangeWallpaper,
});

/// Resolves the routes [snapshot] should reopen, [homeRouteName] being the
/// configured home page.
///
/// A pushed page (the wallpaper preview, the wallpaper groups) is rebuilt over the
/// page it was opened from. A snapshot saved before the base page was recorded has
/// no back target, so the configured home page stands in; that page is rebuilt from
/// its own settings (the explorer reopens at the configured path, not at the one the
/// user was browsing), which is why the stand-in need not be a
/// `restorableSessionRoutes` member itself.
///
/// A base saved under a page that is not normally pushed is ignored rather than
/// honoured: it would fabricate a two-page stack that never existed.
SessionRestorePlan planSessionRestore(SessionRestoreSnapshot snapshot, {required String homeRouteName}) {
  final routeName = snapshot.routeName;
  final isPushed = pushedRestorableSessionRoutes.contains(routeName);
  final savedBase = isPushed ? snapshot.baseRouteName : null;
  // The wallpaper page is not a home page choice, but keeping the stand-in
  // distinct from the top page is what the restore relies on.
  final standInBase = homeRouteName == routeName ? CollectionPage.routeName : homeRouteName;
  return (
    routeName: routeName,
    filters: routeName == CollectionPage.routeName ? snapshot.filters : null,
    baseRouteName: isPushed ? savedBase ?? standInBase : null,
    // Only a recorded collection base carries its set; a stand-in collection
    // keeps the configured home collection.
    baseFilters: savedBase == CollectionPage.routeName ? snapshot.baseFilters : null,
    // The shell renders the wallpaper page from the range route, so the flag only
    // means something there.
    rangeWallpaper: snapshot.rangeWallpaper && routeName == VisibleRangePage.routeName,
  );
}
