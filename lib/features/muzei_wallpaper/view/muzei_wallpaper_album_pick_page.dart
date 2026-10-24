import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_filter_pick_page.dart';
import 'package:aves/model/app_inventory.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/grouping/common.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/action_mixins/vault_aware.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/album_set.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Album grid for the wallpaper source, shaped like Aves' album page.
///
/// Tapping an album opens its media set (images only) with a confirm button;
/// long-pressing starts a multi-selection whose union is previewed the same
/// way. Unlike a normal album page the grid never opens the collection route,
/// because its result has to travel back to the wallpaper settings.
class MuzeiWallpaperAlbumPickPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/albums';

  final CollectionSource source;
  final Uri? initialGroup;

  const new({
    super.key,
    required this.source,
    required this.initialGroup,
  });

  @override
  State<MuzeiWallpaperAlbumPickPage> createState() => _MuzeiWallpaperAlbumPickPageState();
}

class _MuzeiWallpaperAlbumPickPageState extends State<MuzeiWallpaperAlbumPickPage> with FeedbackMixin, VaultAwareMixin {
  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final ValueNotifier<AppMode> _appModeNotifier = ValueNotifier(.pickFilterInternal);

  CollectionSource get source => widget.source;

  @override
  void dispose() {
    _appBarHeightNotifier.dispose();
    _appModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableProvider<ValueNotifier<AppMode>>.value(
      value: _appModeNotifier,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<FilterGrouping>.value(value: albumGrouping),
          FilterGroupProvider(initialValue: widget.initialGroup),
        ],
        child: Builder(
          // to access filter group provider from subtree context
          builder: (context) {
            return Selector<Settings, (ChipSectionFactor, SortFactor)>(
              selector: (context, s) => (s.albumSectionFactor, s.albumSortFactor),
              builder: (context, _, child) {
                return ListenableBuilder(
                  listenable: appInventory.areAppNamesReadyNotifier,
                  builder: (context, child) {
                    return ListenableBuilder(
                      listenable: Listenable.merge({albumGrouping, dynamicAlbums}),
                      builder: (context, child) => StreamBuilder<AlbumsChangedEvent>(
                        stream: source.eventBus.on<AlbumsChangedEvent>(),
                        builder: (context, _) {
                          final groupUri = context.watch<FilterGroupNotifier>().value;
                          final gridItems = _imagesOnly(AlbumListPage.getGridItems(context, source, AlbumChipType.values.toSet(), groupUri));
                          final scrollController = PrimaryScrollController.of(context);
                          return StreamBuilder<Set<CollectionFilter>?>(
                            // to update sections by tier
                            stream: covers.packageChangeStream,
                            builder: (context, _) => SelectionProvider<FilterGridItem<AlbumBaseFilter>>(
                              child: QueryProvider(
                                startEnabled: settings.getShowTitleQuery(context.currentRouteName!),
                                child: FilterGridPage<AlbumBaseFilter>(
                                  // Share the album tab's grid layout so the picker
                                  // feels like the page it mirrors.
                                  settingsRouteKey: AlbumListPage.routeName,
                                  appBar: FilterGridAppBar(
                                    source: source,
                                    title: context.l10n.muzeiWallpaperSourcesChooseAlbum,
                                    actionDelegate: AlbumChipSetActionDelegate(gridItems),
                                    appBarHeightNotifier: _appBarHeightNotifier,
                                    scrollController: scrollController,
                                    onGroupCrumbTap: null,
                                  ),
                                  appBarHeightNotifier: _appBarHeightNotifier,
                                  scrollController: scrollController,
                                  sections: AlbumListPage.groupToSections(context, source, gridItems),
                                  newFilters: source.getNewAlbumFilters(context),
                                  sortFactor: settings.albumSortFactor,
                                  showHeaders: settings.albumSectionFactor != ChipSectionFactor.none,
                                  selectable: true,
                                  emptyBuilder: () => EmptyContent(
                                    icon: AIcons.album,
                                    text: context.l10n.albumEmpty,
                                  ),
                                  heroType: HeroType.never,
                                  floatingActionButton: _buildFab(context),
                                  onTileTap: (gridItem, _) => _onTileTap(context, gridItem),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Drops albums that hold no image, so a wallpaper source can never be an
  /// album that resolves to an empty artwork. Groups are kept: they are the only
  /// way into their members.
  List<FilterGridItem<AlbumBaseFilter>> _imagesOnly(List<FilterGridItem<AlbumBaseFilter>> items) {
    final summaries = source.summaries;
    if (summaries != null) {
      // Entry-free (paged) sources serve album media kinds from the summary
      // domain instead of materializing the library.
      return items.where((item) => item.filter is AlbumGroupFilter || summaries.albumMediaKinds(item.filter).hasImage).toList();
    }
    final entries = source.visibleEntries;
    return items.where((item) => item.filter is AlbumGroupFilter || entries.any((entry) => entry.isImage && item.filter.test(entry))).toList();
  }

  Widget? _buildFab(BuildContext context) {
    return Selector<Selection<FilterGridItem<AlbumBaseFilter>>, (bool, List<AlbumBaseFilter>)>(
      selector: (context, selection) => (selection.isSelecting, selection.selectedItems.map((v) => v.filter).toList()),
      builder: (context, value, child) {
        final (isSelecting, albums) = value;
        if (!isSelecting || albums.isEmpty) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          onPressed: () => unawaited(_previewAlbums(context, albums.toSet())),
          icon: const Icon(AIcons.apply),
          label: Text(context.l10n.muzeiWallpaperSourcesUseSelectedAlbums),
        );
      },
    );
  }

  Future<void> _onTileTap(BuildContext context, FilterGridItem<AlbumBaseFilter> gridItem) async {
    final filter = gridItem.filter;
    final selection = context.read<Selection<FilterGridItem<AlbumBaseFilter>>>();
    if (selection.isSelecting) {
      selection.toggleSelection(gridItem);
      return;
    }
    if (!await unlockFilter(context, filter)) return;
    switch (filter) {
      case AlbumGroupFilter _:
        context.read<FilterGroupNotifier>().value = filter.uri;
      default:
        await _previewAlbums(context, {filter});
    }
  }

  Future<void> _previewAlbums(BuildContext context, Set<AlbumBaseFilter> albums) async {
    if (albums.isEmpty) return;
    final filters = WallpaperSourceScope.filtersForAlbums(albums);
    final confirmed = await Navigator.of(context).push<CollectionFilter>(
      MaterialPageRoute(
        settings: const RouteSettings(name: MuzeiWallpaperFilterPickPage.routeName),
        builder: (_) => MuzeiWallpaperFilterPickPage(
          source: source,
          filter: filters.single,
          multiple: filters.single is SetOrFilter,
        ),
      ),
    );
    if (confirmed == null || !mounted) return;
    Navigator.of(context).pop<Set<CollectionFilter>>(filters);
  }
}
