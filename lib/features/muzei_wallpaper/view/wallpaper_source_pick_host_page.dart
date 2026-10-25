import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/filter_policy_scope.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_filters.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_fab.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_session.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/thumbnail/notifications.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Hosts one wallpaper-source pick in its own navigation sandbox.
///
/// The picker must be the app's real collection and album pages, not copies:
/// tapping an album has to open that album's normal media set, and the drawer
/// and bottom bar have to behave as usual. Those pages navigate with
/// `pushAndRemoveUntil`, though, so on the app's single navigator a tap on the
/// bottom bar would wipe the source page and the wallpaper controller with it.
///
/// This route is the picker's boundary. It gives the pages their own
/// [Navigator], so every navigation they start stays inside the pick, and it
/// provides the pick's state (app mode, hooks, filter policy) above that
/// navigator, so a page pushed later inherits it without being modified. The
/// app's own mode and providers are untouched.
class WallpaperSourcePickHostPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/pick';

  final CollectionSource source;
  final WallpaperSourcePickMode mode;
  final Set<CollectionFilter> initialFilters;

  const new({
    super.key,
    required this.source,
    required this.mode,
    this.initialFilters = const {},
  });

  @override
  State<WallpaperSourcePickHostPage> createState() => _WallpaperSourcePickHostPageState();
}

class _WallpaperSourcePickHostPageState extends State<WallpaperSourcePickHostPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey(debugLabel: 'wallpaper-source-picker');

  late final ValueNotifier<AppMode> _appMode;
  late final WallpaperSourcePickSession _session;
  late final _PickHooks _hooks;
  late final HeroController _heroController;
  late final Set<CollectionFilter> _initialFilters;

  @override
  void initState() {
    super.initState();
    // The picker is the app's own pages, so it uses the app's own pick modes:
    // they navigate, they never take the browse-only surface, and they do not
    // let a long press select media. Only the picker's subtree sees this value.
    _appMode = ValueNotifier(
      widget.mode == WallpaperSourcePickMode.filters ? .pickCollectionFiltersExternal : .pickSingleMediaExternal,
    );
    _session = WallpaperSourcePickSession(
      mode: widget.mode,
      onConfirm: _confirm,
      initialFilters: widget.initialFilters,
    );
    _hooks = _PickHooks(_session);
    // The app's hero controller belongs to the root navigator, which bars it
    // from navigators below it. The picker keeps the chip-to-grid hero by
    // hosting its own.
    _heroController = HeroController(
      createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
    );
    _initialFilters = normalizeWallpaperFilters(widget.initialFilters);
  }

  @override
  void dispose() {
    _heroController.dispose();
    _session.dispose();
    _appMode.dispose();
    super.dispose();
  }

  void _confirm(WallpaperSourcePickResult result) {
    if (!mounted) return;
    // The host is a route on the app's navigator; the inner pages are below it.
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableProvider<ValueNotifier<AppMode>>.value(
      value: _appMode,
      child: CollectionViewHooksScope(
        hooks: _hooks,
        child: FilterPolicyScope(
          // A wallpaper is a still image. The constraint is part of the picker,
          // not a chip the user chose, so it is hidden and cannot be removed.
          hidden: wallpaperPhotoRestriction,
          locked: wallpaperPhotoRestriction,
          child: HeroControllerScope(
            controller: _heroController,
            child: NavigatorPopHandler<Object?>(
              // Back pops the picker's own stack; at its root the host itself
              // pops, which cancels the pick.
              onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
              child: Navigator(
                key: _navigatorKey,
                // The album list answers the common case faster: finding a photo
                // by album, or starting from all photos, does not need the media
                // set first. A configured filter set is a media set, so it opens
                // there. Named pushes come from the app's own destinations; the
                // picker only selects the route, never pushes one by name.
                initialRoute: _session.startsOnAlbums ? AlbumListPage.routeName : CollectionPage.routeName,
                onGenerateInitialRoutes: (navigator, initialRoute) => [_buildStartRoute()],
                onGenerateRoute: (settings) => settings.name == AlbumListPage.routeName ? _buildAlbumRoute(settings) : _buildCollectionRoute(settings),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Route<Object?> _buildStartRoute() {
    return _session.startsOnAlbums ? _buildAlbumRoute(const RouteSettings(name: AlbumListPage.routeName)) : _buildCollectionRoute(const RouteSettings(name: CollectionPage.routeName));
  }

  Route<Object?> _buildCollectionRoute([RouteSettings? settings]) {
    return MaterialPageRoute<Object?>(
      settings: settings ?? const RouteSettings(name: CollectionPage.routeName),
      builder: (_) => CollectionPage(
        source: widget.source,
        filters: _initialFilters,
      ),
    );
  }

  Route<Object?> _buildAlbumRoute([RouteSettings? settings]) {
    return MaterialPageRoute<Object?>(
      settings: settings ?? const RouteSettings(name: AlbumListPage.routeName),
      builder: (_) => const AlbumListPage(initialGroup: null),
    );
  }
}

/// Binds the pick session to the seam the collection pages read.
class _PickHooks implements CollectionViewHooks {
  final WallpaperSourcePickSession session;

  const new(this.session);

  @override
  Set<CollectionFilter?>? augmentFilters(Set<CollectionFilter?>? filters) {
    return session.augmentFilters(filters?.whereType<CollectionFilter>() ?? const <CollectionFilter>{});
  }

  @override
  Set<CollectionFilter> normalizeFilters(Set<CollectionFilter> filters) => session.normalizeFilters(filters);

  @override
  void onViewOpened(CollectionLens collection) => session.adoptView(collection);

  @override
  Widget? buildFab(BuildContext context, CollectionLens collection) {
    return WallpaperSourcePickFab(
      session: session,
      collection: collection,
    );
  }

  @override
  bool onEntryTap(BuildContext context, CollectionLens collection, AvesEntry entry) {
    if (session.isSingle) {
      session.pick(entry);
    } else {
      // The filter set is the answer, so a tap is just a look: open the normal
      // viewer, inside the sandbox.
      OpenViewerNotification(entry).dispatch(context);
    }
    return true;
  }

  @override
  ValueListenable<int?>? get pickedEntryId => session.isSingle ? session.pickedEntryNotifier : null;

  @override
  Set<CollectionFilter>? get mediaSetFilters => session.mediaSetFilters;

  @override
  bool get suppressDoubleBack => true;

  @override
  bool get isPicking => true;

  @override
  bool get allowFilterMutation => false;
}
