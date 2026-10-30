import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/browse_only/services/browse_albums.dart';
import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/view/browse_only_page.dart';
import 'package:aves/features/collection_paging/catalog/catalog_prompt.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/lens/scope_registry.dart';
import 'package:aves/features/collection_paging/view/catalog_prompt_dialog.dart';
import 'package:aves/features/collection_paging/view/collection_import_intro.dart';
import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_restore_bar.dart';
import 'package:aves/features/session_restore/session_restore_collection_state.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/model/highlight.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/collection/collection_grid.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/common/basic/draggable_scrollbar/notifications.dart';
import 'package:aves/widgets/common/basic/insets.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/behaviour/pop/double_back.dart';
import 'package:aves/widgets/common/behaviour/pop/scope.dart';
import 'package:aves/widgets/common/behaviour/pop/tv_navigation.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_fab.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:aves/widgets/navigation/drawer/app_drawer.dart';
import 'package:aves/widgets/navigation/nav_bar/nav_bar.dart';
import 'package:aves/widgets/navigation/tv_rail.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class const CollectionPage({
  super.key,
  required final CollectionSource source,
  required final Set<CollectionFilter?>? filters,
  final bool Function(AvesEntry element)? highlightTest,
}) extends StatefulWidget {
  static const routeName = '/collection';

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> with RouteAware {
  final Set<StreamSubscription> _subscriptions = {};
  late PagedCollectionLens _collection;

  /// The task this view serves, when it is not the library's own view.
  ///
  /// Read once: a page belongs to the task that opened it for its whole life,
  /// so the hooks never change under it.
  CollectionViewHooks? _hooks;

  bool _sessionRouteSubscribed = false;

  final StreamController<DraggableScrollbarEvent> _draggableScrollBarEventStreamController = StreamController.broadcast();
  bool _importing = false;
  int _lastRetryToken = 0;

  @override
  void initState() {
    // do not seed this widget with the collection, but control its lifecycle here instead,
    // as the collection properties may change and they should not be reset by a widget update (e.g. with theme change)
    // The paged lens covers both paths: it serves windows from the database on
    // huge collections and morphs to the exact legacy behaviour otherwise.
    // The lens comes from the scope registry: a view that was shown before is
    // already resolved, so returning to it paints its window instead of
    // resolving the same rows again behind a loading body.
    final hooks = CollectionViewHooksScope.read(context);
    _hooks = hooks;
    _collection = scopeRegistry.acquire(
      source: widget.source,
      // A borrowed view may carry a constraint its opener owns (the wallpaper
      // picker is always photos). Adding it here keeps it out of every page
      // that registered the same filters.
      filters: hooks?.augmentFilters(widget.filters) ?? widget.filters,
    );
    if (hooks != null) {
      hooks.onViewOpened(_collection);
      _collection.filterChangeNotifier.addListener(_onFilterChangedForHooks);
    } else {
      _collection.filterChangeNotifier.addListener(_noteSessionFilters);
      _noteSessionFilters();
    }
    // The media-set slot remembers the view it shows, so the bottom bar's
    // collection item returns to it instead of resetting to the whole library.
    // A view a bottom-bar item declares itself (video, favourites, an album
    // pinned to the bar) belongs to that item and must not hijack the slot, and
    // neither may the bin, which is a drawer page everywhere.
    final routeFilters = (widget.filters ?? const <CollectionFilter?>{}).nonNulls.toSet();
    final declaredFilters = settings.bottomNavigationActions.map((v) => v.filters);
    // A pick is not the media-set view: its filters belong to the caller's
    // intent, and remembering them would make the bottom bar reopen the picker's
    // scope after the picker is gone.
    final picking = context.read<ValueNotifier<AppMode>>().value.isPicking;
    if (!picking && shouldNoteMediaSet(routeFilters, declaredFilters)) {
      mediaSetTab.note(routeFilters: routeFilters, currentFilters: () => _collection.filters);
    }
    super.initState();
    _subscriptions.add(
      settings.updateStream.where((event) => event.key == SettingKeys.enableBinKey).listen((_) {
        if (!settings.enableBin) {
          _collection.removeFilter(TrashFilter.instance);
        }
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInitHighlight());
    // The paged lens holds the catalog backlog back when it is large enough to
    // ask about, and the question is answered here, where dialogs belong. A
    // question raised by another paged surface (explorer, slideshow) is picked
    // up on the next visit to a collection.
    catalogPrompt.pending.addListener(_onCatalogPromptChanged);
    if (catalogPrompt.pending.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askToCatalog());
    }
    // The first import raises a one-time explanation of what the app is doing
    // and how long it takes; dialogs belong here, not in the lens.
    _importing = pagedImportStatus.active;
    pagedImportStatus.addListener(_onImportStatusChanged);
    libraryPhase.addListener(_onLibraryPhaseChanged);
    _lastRetryToken = libraryPhase.retryToken;
    if (pagedImportStatus.explainerPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeExplainImport());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only the library's own collection feeds the session snapshot; a picker's
    // media set belongs to a task that is not restored.
    if (_hooks != null || _sessionRouteSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AvesApp.pageRouteObserver.subscribe(this, route);
      _sessionRouteSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    // Returning from the viewer: the set may have changed while it was open
    // (deletion, an edit that moved the photo).
    _noteSessionFilters();
  }

  /// Remembers the filters the user is browsing for the next cold start.
  ///
  /// The snapshot is only meaningful in the main mode: an external pick or a
  /// viewer launched by another app must not become the restored page.
  void _noteSessionFilters() {
    if (_hooks != null) return;
    if (context.read<ValueNotifier<AppMode>>().value != .main) return;
    sessionRestoreCollectionState.note(
      _collection.filters.where((filter) => !(filter is QueryFilter && filter.live)),
    );
  }

  @override
  void dispose() {
    catalogPrompt.pending.removeListener(_onCatalogPromptChanged);
    pagedImportStatus.removeListener(_onImportStatusChanged);
    libraryPhase.removeListener(_onLibraryPhaseChanged);
    if (_hooks != null) {
      _collection.filterChangeNotifier.removeListener(_onFilterChangedForHooks);
    } else {
      _collection.filterChangeNotifier.removeListener(_noteSessionFilters);
      if (_sessionRouteSubscribed) {
        AvesApp.pageRouteObserver.unsubscribe(this);
        _sessionRouteSubscribed = false;
      }
    }
    _subscriptions
      ..forEach((sub) => sub.cancel())
      ..clear();
    // The lens outlives the page: the scope registry keeps it, so the next visit
    // to this view is a repaint rather than a fresh resolve.
    scopeRegistry.release(_collection);
    super.dispose();
  }

  /// Lets the task that opened this view keep its filters valid.
  ///
  /// The search sheet applies whatever the user picks, including constraints a
  /// borrowed view cannot honour. The rewrite runs after the current
  /// notification so a filter change never re-enters the refresh still
  /// notifying.
  void _onFilterChangedForHooks() {
    final hooks = _hooks;
    if (hooks == null) return;
    if (const SetEquality().equals(hooks.normalizeFilters(_collection.filters), _collection.filters)) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      _collection.setFilters(hooks.normalizeFilters(_collection.filters));
    });
  }

  /// The browser and the collection choose their surface from one place now, so
  /// a phase change rebuilds this page instead of leaving a stale gate behind.
  void _onLibraryPhaseChanged() {
    if (!mounted) return;
    // The handoff is the one moment the browser's window is no longer needed,
    // and this page is the surface that stays mounted through it: clearing from
    // `BrowseOnlyPage.dispose` alone would miss a handoff that happens while
    // that page is not in the tree (a pick, for instance).
    if (libraryPhase.isReady) {
      browseLibrary.clear();
      browseAlbums.clear();
    }
    final token = libraryPhase.retryToken;
    if (token != _lastRetryToken) {
      // The user asked to resume a stopped import: the lens owns the work.
      _lastRetryToken = token;
      if (!_collection.importingRows) _collection.refresh();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final useTvLayout = settings.useTvLayout;
    // While the library is being organized the browser is the collection
    // surface: a window over a database still being written cannot answer for
    // albums, counts or a filter switch without reading as "zero" or
    // "loading". The phase is the only signal and it only moves one way, so a
    // navigation back to all media after the import can never bring the browser
    // back: the grid shows its own loading state instead.
    //
    // A pick never takes the browser: it has nothing selectable and no confirm,
    // so the caller's intent could not be completed at all.
    final browseOnly = libraryPhase.isBrowsing && !context.watch<ValueNotifier<AppMode>>().value.isPicking;
    final liveFilter = _collection.filters.firstWhereOrNull((v) => v is QueryFilter && v.live) as QueryFilter?;
    return SelectionProvider<AvesEntry>(
      toSelectableItems: (entry) => entry.toSelectableItems(),
      keyOf: (entry) => entry.id,
      child: Selector<Selection<AvesEntry>, (bool, int)>(
        selector: (context, selection) => (selection.isSelecting, selection.selectedItemCount),
        builder: (context, selectionResult, child) {
          final (isSelecting, selectedItemCount) = selectionResult;
          final gridBody = QueryProvider(
            startEnabled: settings.getShowTitleQuery(context.currentRouteName!),
            initialQuery: liveFilter?.query,
            child: Builder(
              builder: (context) {
                return AvesPopScope(
                  handlers: [
                    APopHandler(
                      canPop: (context) => context.select<Selection<AvesEntry>, bool>((v) => !v.isSelecting),
                      onPopBlocked: (context) => context.read<Selection<AvesEntry>>().browse(),
                    ),
                    tvNavigationPopHandler,
                    doubleBackPopHandler,
                  ],
                  child: GestureAreaProtectorStack(
                    child: DirectionalSafeArea(
                      start: !useTvLayout,
                      top: false,
                      bottom: false,
                      child: browseOnly
                          ? const BrowseOnlyPage()
                          : const CollectionGrid(
                              // key is expected by test driver
                              key: Key('collection-grid'),
                              settingsRouteKey: CollectionPage.routeName,
                            ),
                    ),
                  ),
                );
              },
            ),
          );
          // The grouped wallpaper notice is above the grid, not inside it: the
          // loss happens while the app is not running, so it belongs where the
          // user lands rather than in the scrollable content they may never
          // reach.
          final body = GroupedWallpaperRestoreBody(child: gridBody);

          Widget page;
          if (useTvLayout) {
            page = AvesScaffold(
              body: Row(
                children: [
                  TvRail(
                    controller: context.read<TvRailController>(),
                    currentCollection: _collection,
                  ),
                  Expanded(child: body),
                ],
              ),
              resizeToAvoidBottomInset: false,
              extendBody: true,
            );
          } else {
            page = Selector<Settings, bool>(
              selector: (context, s) => s.enableBottomNavigationBar,
              builder: (context, enableBottomNavigationBar, child) {
                final canNavigate = context.select<ValueNotifier<AppMode>, bool>((v) => v.value.canNavigate);
                final showBottomNavigationBar = canNavigate && enableBottomNavigationBar;

                return NotificationListener<DraggableScrollbarNotification>(
                  onNotification: (notification) {
                    _draggableScrollBarEventStreamController.add(notification.event);
                    return false;
                  },
                  child: AvesScaffold(
                    body: body,
                    floatingActionButton: _buildFab(context, isSelecting, selectedItemCount, browseOnly: browseOnly),
                    drawer: canNavigate ? AppDrawer(currentCollection: _collection) : null,
                    // The browser brings its own bar (the same items, mapped to
                    // views it can serve); two bars would fight for the bottom.
                    bottomNavigationBar: showBottomNavigationBar && !browseOnly
                        ? AppBottomNavBar(
                            events: _draggableScrollBarEventStreamController.stream,
                            currentCollection: _collection,
                          )
                        : null,
                    resizeToAvoidBottomInset: false,
                    extendBody: true,
                  ),
                );
              },
            );
          }
          // this provider should be above `TvRail`
          return ChangeNotifierProvider<CollectionLens>.value(
            value: _collection,
            child: page,
          );
        },
      ),
    );
  }

  Widget? _buildFab(BuildContext context, bool isSelecting, int selectedItemCount, {required bool browseOnly}) {
    // Nothing on the browser is selectable: a floating action over it would be
    // a button with no valid target.
    if (browseOnly) return null;
    // A borrowed view answers a question instead of acting on the library, so
    // its opener supplies the button.
    final hookedFab = _hooks?.buildFab(context, _collection);
    if (hookedFab != null) return hookedFab;
    final actionDelegate = EntrySetActionDelegate();
    final action = EntrySetActions.fab.firstWhereOrNull((action) {
      return actionDelegate.isVisible(
        action,
        appMode: context.watch<ValueNotifier<AppMode>>().value,
        isSelecting: isSelecting,
        itemCount: _collection.entryCount,
        selectedItemCount: selectedItemCount,
        isTrash: _collection.filters.contains(TrashFilter.instance),
      );
    });

    if (action != null) {
      final canApply = actionDelegate.canApply(
        action,
        isSelecting: isSelecting,
        collection: _collection,
        selectedItemCount: selectedItemCount,
      );

      return AvesFab(
        tooltip: action.getText(context),
        icon: action.getIcon(),
        onPressed: canApply ? () => actionDelegate.onActionSelected(context, action) : null,
      );
    }

    return null;
  }

  Future<void> _checkInitHighlight() async {
    final highlightTest = widget.highlightTest;
    if (highlightTest == null) return;

    final item = await _collection.firstMatching(highlightTest);
    if (item == null) return;

    final delayDuration = context.read<DurationsData>().staggeredAnimationPageTarget;
    await Future.delayed(delayDuration + ADurations.highlightScrollInitDelay);

    if (!mounted) return;
    final animate = context.read<Settings>().animate;
    context.read<HighlightInfo>().trackItem(item, animate: animate, highlightItem: item);
  }

  void _onCatalogPromptChanged() {
    if (catalogPrompt.pending.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _askToCatalog());
  }

  Future<void> _askToCatalog() async {
    final count = catalogPrompt.pending.value;
    if (!mounted || count == null) return;
    // Taken over here, so a second paged surface resolving while the dialog is
    // up does not raise it again.
    catalogPrompt.resolve();
    final answer = await showCatalogPromptDialog(context, count: count);
    if (!mounted || answer == null) return;
    if (!await applyCatalogPromptAnswer(answer)) return;
    if (!mounted) return;
    unawaited(_collection.runCatalogBacklog());
  }

  void _onImportStatusChanged() {
    final importing = pagedImportStatus.active;
    final wasImporting = _importing;
    _importing = importing;
    if (wasImporting && !importing && mounted) {
      // The reduced mode ended on its own: its strip and the app bar's
      // "organizing" line simply disappear, so say once that the features are
      // back instead of leaving the user to notice it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // A pushed viewer or page owns the screen: the notice would land on it.
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.browseOnlyUnlockedFeedback)),
        );
      });
    }
    if (!pagedImportStatus.explainerPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeExplainImport());
  }

  /// Shows the one-time explanation of the first import.
  ///
  /// Delayed a beat so it never competes with the first frame it is explaining,
  /// and taken over synchronously so a second listener cannot raise it twice.
  Future<void> _maybeExplainImport() async {
    if (!mounted || !pagedImportStatus.explainerPending) return;
    pagedImportStatus.clearExplainer();
    await collectionPagingPrefs.setImportExplained();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await showCollectionImportIntroDialog(context, libraryCount: pagedImportStatus.total);
  }
}
