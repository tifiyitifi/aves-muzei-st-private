import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/lens/paged_bootstrap.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/drift_db/migration/widgets/legacy_import_indicator.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_page.dart';
import 'package:aves/features/session_restore/session_restore_plan.dart';
import 'package:aves/features/session_restore/session_restore_store.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/geo/uri.dart';
import 'package:aves/locale/intl.dart';
import 'package:aves/model/app/intent.dart';
import 'package:aves/model/app/permissions.dart';
import 'package:aves/model/app_inventory.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/catalog.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/analysis_service.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/global_search.dart';
import 'package:aves/services/intent_service.dart';
import 'package:aves/services/widget_service.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/behaviour/routes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/search/page.dart';
import 'package:aves/widgets/editor/entry_editor_page.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/tags_page.dart';
import 'package:aves/widgets/home/home_error.dart';
import 'package:aves/widgets/map/map_page.dart';
import 'package:aves/widgets/search/collection_search_page_route.dart';
import 'package:aves/widgets/settings/home_widget_settings_page.dart';
import 'package:aves/widgets/settings/screen_saver_settings_page.dart';
import 'package:aves/widgets/settings/settings_page.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:aves/widgets/viewer/screen_saver_page.dart';
import 'package:aves/widgets/wallpaper_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class const HomePage({
  super.key,
  final Map<String, Object?>? intentData,
}) extends StatefulWidget {
  static const routeName = '/';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with FeedbackMixin {
  AvesEntry? _viewerEntry;
  int? _widgetId;
  String? _initialRouteName, _initialSearchQuery;
  Set<CollectionFilter>? _initialFilters;

  /// The wallpaper view route the intent asked for, pushed over the home page.
  ///
  /// A gesture opens the view from the wallpaper, which has no Activity of its
  /// own: without a page below it, back would exit the app. The route is still
  /// the app's own page, so the normal home is pushed first.
  String? _intentOverlayRouteName;
  String? _restoredBaseRouteName;
  Set<CollectionFilter>? _restoredBaseFilters;
  String? _initialExplorerPath;
  (LatLng, double?)? _initialLocationZoom;
  List<String>? _secureUris;
  (Object, StackTrace)? _setupError;

  static const allowedShortcutRoutes = [
    AlbumListPage.routeName,
    CollectionPage.routeName,
    ExplorerPage.routeName,
    MapPage.routeName,
    MuzeiWallpaperPage.routeName,
    GroupedWallpaperViewPage.routeName,
    VisibleRangePage.routeName,
    SearchPage.routeName,
    SettingsPage.routeName,
  ];

  /// Routes a wallpaper gesture opens, which are pushed over the app's home.
  ///
  /// The gesture comes from a live wallpaper, so the intent is a cold start with
  /// no page below it; keeping the home page underneath makes back return to the
  /// app instead of closing it.
  static const wallpaperOverlayRoutes = {
    MuzeiWallpaperPage.routeName,
    GroupedWallpaperViewPage.routeName,
  };

  @override
  void initState() {
    super.initState();
    _setup();
    imageCache.maximumSize = 1000;
    imageCache.maximumSizeBytes = 100 * (1 << 20); // MiB
  }

  @override
  Widget build(BuildContext context) => AvesScaffold(
    body: _setupError != null
        ? HomeError(
            error: _setupError!.$1,
            stack: _setupError!.$2,
          )
        : const LegacyImportIndicator(),
  );

  Future<void> _setup() async {
    try {
      final stopwatch = Stopwatch()..start();
      if (await windowService.isActivity()) {
        // do not check whether permission was granted, because some app stores
        // hide in some countries apps that force quit on permission denial
        await Permissions.mediaAccess.request();
      }

      AppMode appMode = .main;
      var error = false;
      final Map<String, Object?> intentData = widget.intentData ?? await IntentService.getIntentData();
      final debug = intentData[IntentDataKeys.debug] as bool? ?? false;
      final intentAction = intentData[IntentDataKeys.action] as String?;
      _initialFilters = null;
      _initialExplorerPath = null;
      _secureUris = null;

      // A plain launch has no intent asking for a specific page: reopen the one
      // the user was on when Android killed the process. An intent always wins,
      // and a task swiped from recents has already cleared the snapshot.
      // `ACTION_MAIN` itself is not exposed as `IntentDataKeys.action`, only the
      // extras it carries, so their absence is what identifies a plain launch.
      final isPlainLaunch = intentAction == null &&
          intentData[IntentDataKeys.debug] != true &&
          intentData[IntentDataKeys.page] == null &&
          intentData[IntentDataKeys.filters] == null &&
          intentData[IntentDataKeys.uri] == null &&
          intentData[IntentDataKeys.explorerPath] == null;
      if (isPlainLaunch) {
        final snapshot = await sessionRestoreStore.load();
        if (snapshot != null) {
          // The plan also covers a snapshot saved before the base page was
          // recorded, which needs a page to go back to.
          final plan = planSessionRestore(snapshot, homeRouteName: settings.homeNavItem.route);
          _initialRouteName = plan.routeName;
          _initialFilters = plan.filters;
          _restoredBaseRouteName = plan.baseRouteName;
          _restoredBaseFilters = plan.baseFilters;
        }
      }

      if (debug) {
        await localMediaDb.init();
        final logs = await localMediaDb.loadAllDebugLog();

        final date = DateFormat('yyyyMMdd_HHmmss', IntlUtils.rootLocaleName).format(DateTime.now());
        final success = await storageService.createFile(
          basename: 'aves_debug_logs-$date}',
          mimeType: MimeTypes.plainText,
          bytes: Uint8List.fromList(utf8.encode(logs.join('\n'))),
        );
        if (success != null) {
          if (success) {
            showFeedback(context, FeedbackType.info, context.l10n.genericSuccessFeedback);
          } else {
            showFeedback(context, FeedbackType.warn, context.l10n.genericFailureFeedback);
          }
        }
        unawaited(
          Navigator.maybeOf(context)?.pushAndRemoveUntil(
            await _getRedirectRoute(appMode),
            (route) => false,
          ),
        );
        return;
      }

      await availability.onNewIntent();
      await androidFileUtils.init();
      if (!{
            IntentActions.edit,
            IntentActions.screenSaver,
            IntentActions.setWallpaper,
          }.contains(intentAction) &&
          settings.isInstalledAppAccessAllowed) {
        unawaited(appInventory.initAppNames());
      }

      if (intentData.values.nonNulls.isNotEmpty) {
        await reportService.log('Intent data=$intentData');
        var intentUri = intentData[IntentDataKeys.uri] as String?;
        final intentMimeType = intentData[IntentDataKeys.mimeType] as String?;

        switch (intentAction) {
          case IntentActions.appSettings:
            _initialRouteName = SettingsPage.routeName;
          case IntentActions.view:
            appMode = .view;
            _secureUris = (intentData[IntentDataKeys.secureUris] as List?)?.cast<String>();
          case IntentActions.viewGeo:
            error = true;
            if (intentUri != null) {
              final locationZoom = parseGeoUri(intentUri);
              if (locationZoom != null) {
                _initialRouteName = MapPage.routeName;
                _initialLocationZoom = locationZoom;
                error = false;
              }
            }
            break;
          case IntentActions.edit:
            appMode = .edit;
          case IntentActions.setWallpaper:
            appMode = .setWallpaper;
          case IntentActions.pickItems:
            // TODO TLAD apply pick mimetype(s)
            // some apps define multiple types, separated by a space (maybe other signs too, like `,` `;`?)
            final multiple = (intentData[IntentDataKeys.allowMultiple] as bool?) ?? false;
            debugPrint('pick mimeType=$intentMimeType multiple=$multiple');
            appMode = multiple ? .pickMultipleMediaExternal : .pickSingleMediaExternal;
          case IntentActions.pickCollectionFilters:
            appMode = .pickCollectionFiltersExternal;
          case IntentActions.screenSaver:
            appMode = .screenSaver;
            _initialRouteName = ScreenSaverPage.routeName;
          case IntentActions.screenSaverSettings:
            _initialRouteName = ScreenSaverSettingsPage.routeName;
          case IntentActions.search:
            _initialRouteName = SearchPage.routeName;
            _initialSearchQuery = intentData[IntentDataKeys.query] as String?;
          case IntentActions.widgetSettings:
            _initialRouteName = HomeWidgetSettingsPage.routeName;
            _widgetId = (intentData[IntentDataKeys.widgetId] as int?) ?? 0;
          case IntentActions.widgetOpen:
            final widgetId = intentData[IntentDataKeys.widgetId] as int?;
            if (widgetId == null) {
              error = true;
            } else {
              // widget settings may be modified in a different process after channel setup
              await settings.reload();
              final page = settings.getWidgetOpenPage(widgetId);
              switch (page) {
                case .collection:
                  _initialFilters = settings.getWidgetCollectionFilters(widgetId);
                case .viewer:
                  appMode = .view;
                  intentUri = settings.getWidgetUri(widgetId);
                case .home:
                case .updateWidget:
                  break;
              }
              unawaited(WidgetService.update(widgetId));
            }
          default:
            // do not use 'route' as extra key, as the Flutter framework acts on it
            final extraRoute = intentData[IntentDataKeys.page] as String?;
            if (allowedShortcutRoutes.contains(extraRoute)) {
              _initialRouteName = extraRoute;
              if (wallpaperOverlayRoutes.contains(extraRoute)) {
                _intentOverlayRouteName = extraRoute;
              }
            }
        }
        if (_initialFilters == null) {
          final serializedFilters = (intentData[IntentDataKeys.filters] as List?)?.cast<String>();
          _initialFilters = serializedFilters?.map(CollectionFilter.fromJson).nonNulls.toSet();
        }
        _initialExplorerPath = intentData[IntentDataKeys.explorerPath] as String?;

        switch (appMode) {
          case .view:
          case .edit:
          case .setWallpaper:
            await _initViewerEssentials();
            if (intentUri != null) {
              _viewerEntry = await _initViewerEntry(
                uri: intentUri,
                mimeType: intentMimeType,
              );
            }
            error = _viewerEntry == null;
          default:
            break;
        }
      }

      if (error) {
        debugPrint('Failed to init app mode=$appMode for intent data=$intentData. Fallback to main mode.');
        appMode = .main;
      }

      context.read<ValueNotifier<AppMode>>().value = appMode;
      unawaited(reportService.setCustomKey('app_mode', appMode.toString()));

      switch (appMode) {
        case .main:
        case .pickCollectionFiltersExternal:
        case .pickSingleMediaExternal:
        case .pickMultipleMediaExternal:
          unawaited(GlobalSearch.registerCallback());
          unawaited(AnalysisService.registerCallback());
          final source = context.read<CollectionSource>();
          if (source.loadedScope != CollectionSource.fullScope) {
            await reportService.log('Initialize source to start app with mode=$appMode, loaded scope=${source.loadedScope}');
            // Huge libraries start paged (entry-free essentials only) instead of
            // materializing everything; small ones keep the legacy full load.
            final decision = await const CollectionEngineRouter().resolve(filters: CollectionSource.fullScope);
            // A legacy decision is only honoured when a full load is provably
            // safe: an unsupported scope (locked vault, non-Gregorian sections)
            // on a huge library bootstraps paged instead, and the collection view
            // then explains why it cannot be shown, rather than materializing the
            // whole library here.
            if (decision.route == CollectionRoute.paged || !await const CollectionEngineRouter().allowFullLoad()) {
              await PagedBootstrap.ensure(source);
            } else {
              final loadTopEntriesFirst = settings.homeNavItem.route == CollectionPage.routeName && settings.homeCustomCollection.isEmpty;
              source.canAnalyze = true;
              await source.init(scope: CollectionSource.fullScope, loadTopEntriesFirst: loadTopEntriesFirst);
            }
          }
        case .screenSaver:
          await reportService.log('Initialize source to start screen saver');
          final source = context.read<CollectionSource>();
          source.canAnalyze = false;
          // A huge screen saver scope must not be fully loaded either: the paged
          // path bootstraps entry-free and plays a window-backed permutation.
          final screenSaverDecision = await const CollectionEngineRouter().resolve(filters: settings.screenSaverCollectionFilters);
          if (screenSaverDecision.route == CollectionRoute.paged || !await const CollectionEngineRouter().allowFullLoad()) {
            await PagedBootstrap.ensure(source);
          } else {
            await source.init(scope: settings.screenSaverCollectionFilters);
          }
        case .view:
          if (_isViewerSourceable(_viewerEntry) && _secureUris == null) {
            final directory = _viewerEntry?.directory;
            if (directory != null) {
              unawaited(AnalysisService.registerCallback());
              await reportService.log('Initialize source to view item in directory $directory');
              final source = context.read<CollectionSource>();
              final albumFilters = {StoredAlbumFilter(directory, null)};
              // A huge album must not be fully loaded just to show one item:
              // the paged path bootstraps entry-free and resolves the opened
              // entry's index from the database.
              final viewDecision = await const CollectionEngineRouter().resolve(filters: albumFilters);
              if (viewDecision.route == CollectionRoute.paged || !await const CollectionEngineRouter().allowFullLoad()) {
                await PagedBootstrap.ensure(source);
              } else {
                // analysis is necessary to display neighbour items when the initial item is a new one
                source.canAnalyze = true;
                await source.init(scope: albumFilters);
              }
            }
          }
        default:
          break;
      }

      debugPrint('Home setup complete in ${stopwatch.elapsed.inMilliseconds}ms');

      // `pushReplacement` is not enough in some edge cases
      // e.g. when opening the viewer in `view` mode should replace a viewer in `main` mode
      final navigator = Navigator.maybeOf(context);
      if (navigator != null) {
        final baseRouteName = _restoredBaseRouteName;
        if (baseRouteName != null) {
          // A page pushed over another one (the wallpaper preview) is restored
          // over the page it was opened from, so backing out returns there
          // instead of leaving the app.
          final topRoute = await _getRedirectRoute(appMode);
          final baseRoute = await _getRedirectRoute(
            appMode,
            overrideRouteName: baseRouteName,
            overrideFilters: _restoredBaseFilters,
          );
          // Both calls apply synchronously, so the base is already on the stack
          // when the top page follows. Their futures are `route.popped` and
          // complete only on a pop, so they must stay unawaited: awaiting the
          // first would hold the restore until the base page is left.
          unawaited(navigator.pushAndRemoveUntil(baseRoute, (route) => false));
          unawaited(navigator.push(topRoute));
        } else if (_intentOverlayRouteName != null) {
          // A wallpaper gesture cold-started a view, which has no page below it.
          // Keep the normal home page underneath, so back returns to the app
          // instead of closing it.
          final baseRoute = await _getRedirectRoute(
            appMode,
            overrideRouteName: settings.homeNavItem.route,
            useIntentFilters: false,
          );
          final topRoute = await _getRedirectRoute(appMode);
          unawaited(navigator.pushAndRemoveUntil(baseRoute, (route) => false));
          unawaited(navigator.push(topRoute));
        } else {
          unawaited(
            navigator.pushAndRemoveUntil(
              await _getRedirectRoute(appMode),
              (route) => false,
            ),
          );
        }
      }
    } catch (error, stack) {
      debugPrint('failed to setup app with error=$error\n$stack');
      setState(() => _setupError = (error, stack));
    }
  }

  Future<void> _initViewerEssentials() async {
    // for video playback storage, debug log
    await localMediaDb.init();
  }

  bool _isViewerSourceable(AvesEntry? viewerEntry) {
    return viewerEntry != null && viewerEntry.directory != null && !settings.hiddenFilters.any((filter) => filter.test(viewerEntry));
  }

  /// The real entry at [index] of [copy], after prefetching its window; null
  /// when the position could not be materialized.
  Future<AvesEntry?> _resolvePagedViewEntry(PagedViewerCopy copy, int index) async {
    await copy.prefetchAround(index);
    final entry = copy.entryAt(index);
    return entry is SkeletonEntry ? null : entry;
  }

  /// Exact legacy view collection: an in-memory album lens that does not stack
  /// bursts/RAWs, so opening a sub-entry selects the containing main entry.
  ///
  /// Returns null (and disposes the collection) when the album does not contain
  /// [viewerEntry]; otherwise reports the collection's own instance through
  /// [onResolved], so the viewer pages through the lens rather than the
  /// transient entry fetched from the intent.
  Future<CollectionLens?> _legacyViewCollection(
    CollectionSource source,
    Set<CollectionFilter> filters,
    AvesEntry viewerEntry,
    void Function(AvesEntry resolved) onResolved,
  ) async {
    final collection = CollectionLens(
      source: source,
      filters: filters,
      listenToSource: true,
      stackBursts: false,
      stackDevelopedRaws: false,
    );
    // useful when opening transient images from camera apps
    await source.checkForChanges();
    final resolved = collection.sortedEntries.firstWhereOrNull((entry) => entry.uri == viewerEntry.uri || entry.path == viewerEntry.path);
    if (resolved == null) {
      collection.dispose();
      return null;
    }
    onResolved(resolved);
    return collection;
  }

  Future<AvesEntry?> _initViewerEntry({required String uri, required String? mimeType}) async {
    if (uri.startsWith('/')) {
      // convert this file path to a proper URI
      uri = Uri.file(uri).toString();
    }
    final entry = await mediaFetchService.getEntry(uri, mimeType);
    if (entry != null) {
      // cataloguing is essential for coordinates and video rotation
      await entry.catalog(background: false, force: false, persist: false);
    }
    return entry;
  }

  Future<Route> _getRedirectRoute(
    AppMode appMode, {
    String? overrideRouteName,
    Set<CollectionFilter>? overrideFilters,
    bool useIntentFilters = true,
  }) async {
    String routeName;
    Set<CollectionFilter?>? filters;
    switch (appMode) {
      case .setWallpaper:
        return DirectMaterialPageRoute(
          settings: const RouteSettings(name: WallpaperPage.routeName),
          builder: (_) {
            return WallpaperPage(
              entry: _viewerEntry,
            );
          },
        );
      case .view:
        AvesEntry viewerEntry = _viewerEntry!;
        CollectionLens? collection;

        final source = context.read<CollectionSource>();
        final album = viewerEntry.directory;
        if (album != null) {
          // wait for collection to pass the `loading` state
          final loadingCompleter = Completer();
          final stateNotifier = source.stateNotifier;
          void _onSourceStateChanged() {
            if (stateNotifier.value != SourceState.loading) {
              stateNotifier.removeListener(_onSourceStateChanged);
              loadingCompleter.complete();
            }
          }

          stateNotifier.addListener(_onSourceStateChanged);
          _onSourceStateChanged();
          await loadingCompleter.future;

          final filters = {StoredAlbumFilter(album, source.getStoredAlbumDisplayName(context, album))};
          final decision = await const CollectionEngineRouter().resolve(filters: filters);
          // One probe covers both branches: a paged decision never asks, and a
          // legacy one asks once and reuses the answer below.
          final allowFullLoad = decision.route != CollectionRoute.paged && await const CollectionEngineRouter().allowFullLoad();
          // A scope below the size threshold still carries its predicate, so a
          // small album in a library too large to load pages like any other view:
          // only a scope with no windowed form opens the entry alone.
          final paged = decision.route == CollectionRoute.paged || (!allowFullLoad && decision.predicate != null);
          if (paged) {
            // Window-backed viewer: the opened entry's index comes from the
            // database order, so the neighbours resolve without any window
            // being materialized up front.
            final lens = PagedCollectionLens(source: source, filters: filters);
            await lens.ready;
            if (lens.pagedActive) {
              final copy = PagedViewerCopy(parent: lens, ownsParent: true);
              final index = await lens.indexOfId(viewerEntry.id);
              final resolved = index >= 0 ? await _resolvePagedViewEntry(copy, index) : null;
              if (resolved != null) {
                viewerEntry = resolved;
                collection = copy;
              } else {
                debugPrint('collection does not contain viewerEntry=$viewerEntry');
                copy.dispose();
                collection = null;
              }
            } else {
              // Morphed after all: fall back to the exact legacy path.
              lens.dispose();
              collection = await _legacyViewCollection(source, filters, viewerEntry, (resolved) => viewerEntry = resolved);
            }
          } else if (allowFullLoad) {
            collection = await _legacyViewCollection(source, filters, viewerEntry, (resolved) => viewerEntry = resolved);
          } else {
            // The album cannot be windowed (e.g. a locked vault) and the library
            // must not be materialized to show one item: open the entry alone.
            debugPrint('view: album $album cannot be paged and a full load is not safe, showing $viewerEntry alone');
            collection = null;
          }
        }

        return DirectMaterialPageRoute(
          settings: const RouteSettings(name: EntryViewerPage.routeName),
          builder: (_) {
            return EntryViewerPage(
              collection: collection,
              initialEntry: viewerEntry,
            );
          },
        );
      case .edit:
        return DirectMaterialPageRoute(
          settings: const RouteSettings(name: EntryViewerPage.routeName),
          builder: (_) {
            return ImageEditorPage(
              entry: _viewerEntry!,
            );
          },
        );
      case .initialization:
      case .main:
      case .pickCollectionFiltersExternal:
      case .pickSingleMediaExternal:
      case .pickMultipleMediaExternal:
      case .pickFilteredMediaInternal:
      case .pickUnfilteredMediaInternal:
      case .pickFilterInternal:
      case .previewMap:
      case .screenSaver:
      case .slideshow:
        routeName = overrideRouteName ?? _initialRouteName ?? settings.homeNavItem.route;
        filters = overrideFilters ?? (useIntentFilters ? _initialFilters : null) ?? (routeName == CollectionPage.routeName ? settings.homeCustomCollection : {});
    }
    Route buildRoute(WidgetBuilder builder) => DirectMaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: builder,
    );

    final source = context.read<CollectionSource>();
    switch (routeName) {
      case AlbumListPage.routeName:
        return buildRoute((context) => const AlbumListPage(initialGroup: null));
      case TagListPage.routeName:
        return buildRoute((context) => const TagListPage(initialGroup: null));
      case MapPage.routeName:
        return buildRoute((context) {
          // Not windowed: the map walks the whole scope to cluster its markers
          // and to build item tracks, so a lazy list would page the library in
          // from under it. A huge library therefore keeps the in-memory path,
          // which shows no marker (see Known Issues).
          final mapCollection = CollectionLens(
            source: source,
            filters: {
              LocationFilter.located,
              ...?filters,
            },
          );
          return MapPage(
            collection: mapCollection,
            initialLocation: _initialLocationZoom?.$1,
            initialZoom: _initialLocationZoom?.$2,
          );
        });
      case ExplorerPage.routeName:
        final path = _initialExplorerPath ?? settings.homeCustomExplorerPath;
        return buildRoute((context) => ExplorerPage(path: path));
      case HomeWidgetSettingsPage.routeName:
        return buildRoute((context) => HomeWidgetSettingsPage(widgetId: _widgetId!));
      case MuzeiWallpaperPage.routeName:
        return buildRoute((context) => const MuzeiWallpaperPage());
      case GroupedWallpaperViewPage.routeName:
        return buildRoute((context) => const GroupedWallpaperViewPage());
      case VisibleRangePage.routeName:
        return buildRoute((context) => const VisibleRangeShellPage());
      case ScreenSaverPage.routeName:
        return buildRoute((context) => ScreenSaverPage(source: source));
      case ScreenSaverSettingsPage.routeName:
        return buildRoute((context) => const ScreenSaverSettingsPage());
      case SearchPage.routeName:
        return CollectionSearchPageRoute(
          context: context,
          canPop: false,
          initialQuery: _initialSearchQuery,
        );
      case SettingsPage.routeName:
        return buildRoute((context) => const SettingsPage());
      case CollectionPage.routeName:
      default:
        return buildRoute((context) => CollectionPage(source: source, filters: filters));
    }
  }
}
