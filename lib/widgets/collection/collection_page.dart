import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/catalog/catalog_prompt.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/catalog_prompt_dialog.dart';
import 'package:aves/features/collection_paging/view/collection_import_intro.dart';
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

class _CollectionPageState extends State<CollectionPage> {
  final Set<StreamSubscription> _subscriptions = {};
  late PagedCollectionLens _collection;
  final StreamController<DraggableScrollbarEvent> _draggableScrollBarEventStreamController = StreamController.broadcast();

  @override
  void initState() {
    // do not seed this widget with the collection, but control its lifecycle here instead,
    // as the collection properties may change and they should not be reset by a widget update (e.g. with theme change)
    // The paged lens covers both paths: it serves windows from the database on
    // huge collections and morphs to the exact legacy behaviour otherwise.
    _collection = PagedCollectionLens(
      source: widget.source,
      filters: widget.filters,
    );
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
    pagedImportStatus.addListener(_onImportStatusChanged);
    if (pagedImportStatus.explainerPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeExplainImport());
    }
  }

  @override
  void dispose() {
    catalogPrompt.pending.removeListener(_onCatalogPromptChanged);
    pagedImportStatus.removeListener(_onImportStatusChanged);
    _subscriptions
      ..forEach((sub) => sub.cancel())
      ..clear();
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useTvLayout = settings.useTvLayout;
    final liveFilter = _collection.filters.firstWhereOrNull((v) => v is QueryFilter && v.live) as QueryFilter?;
    return SelectionProvider<AvesEntry>(
      toSelectableItems: (entry) => entry.toSelectableItems(),
      keyOf: (entry) => entry.id,
      child: Selector<Selection<AvesEntry>, (bool, int)>(
        selector: (context, selection) => (selection.isSelecting, selection.selectedItemCount),
        builder: (context, selectionResult, child) {
          final (isSelecting, selectedItemCount) = selectionResult;
          final body = QueryProvider(
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
                      child: const CollectionGrid(
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
                    floatingActionButton: _buildFab(context, isSelecting, selectedItemCount),
                    drawer: canNavigate ? AppDrawer(currentCollection: _collection) : null,
                    bottomNavigationBar: showBottomNavigationBar
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

  Widget? _buildFab(BuildContext context, bool isSelecting, int selectedItemCount) {
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
