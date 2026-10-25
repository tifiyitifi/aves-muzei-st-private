import 'dart:async';

import 'package:aves/features/browse_only/view/browse_albums_view.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/summary/ensure_album_list.dart';
import 'package:aves/model/app_inventory.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/grouping/common.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/album_set.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves/widgets/filter_grids/common/filter_nav_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class AlbumListPage extends StatefulWidget {
  static const routeName = '/albums';

  final Uri? initialGroup;

  const new({
    super.key,
    required this.initialGroup,
  });

  @override
  State<AlbumListPage> createState() => _AlbumListPageState();

  /// The album grid's items, shared with the pick dialogs.
  static List<FilterGridItem<AlbumBaseFilter>> getGridItems(
    BuildContext context,
    CollectionSource source,
    Set<AlbumChipType> albumChipTypes,
    Uri? groupUri,
  ) => _AlbumListPageState.getGridItems(context, source, albumChipTypes, groupUri);

  /// The album grid's sections, shared with the pick dialogs.
  static Map<ChipSectionKey, List<FilterGridItem<AlbumBaseFilter>>> groupToSections(
    BuildContext context,
    CollectionSource source,
    Iterable<FilterGridItem<AlbumBaseFilter>> sortedMapEntries,
  ) => _AlbumListPageState.groupToSections(context, source, sortedMapEntries);
}

class _AlbumListPageState extends State<AlbumListPage> {
  /// The source whose album data was requested, so a dependency change does not
  /// start the same load twice.
  CollectionSource? _ensuredSource;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The album list has to work when no collection lens ran in this process:
    // this page is a top-level destination of its own, and the wallpaper picker
    // can open it first. An entry-free source answers from the database, which
    // only this call makes sure is loaded.
    final source = context.read<CollectionSource>();
    if (identical(source, _ensuredSource)) return;
    _ensuredSource = source;
    unawaited(ensureAlbumListData(source));
  }

  @override
  Widget build(BuildContext context) {
    // One phase decides which album list is honest: while the library is not
    // imported the database holds only the rows the import has written, so its
    // summaries would list a partial library (or nothing) as if that were the
    // whole answer. The builder listens, so the persisted flag arriving a frame
    // after the page was built cannot leave the browse album page on screen.
    return ListenableBuilder(
      listenable: libraryPhase,
      builder: (context, child) => libraryPhase.isBrowsing ? const BrowseOnlyAlbumsPage() : child!,
      child: _buildAlbums(context),
    );
  }

  Widget _buildAlbums(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FilterGrouping>.value(value: albumGrouping),
        FilterGroupProvider(initialValue: widget.initialGroup),
      ],
      child: Builder(
        // to access filter group provider from subtree context
        builder: (context) {
          final source = context.read<CollectionSource>();
          return Selector<Settings, (ChipSectionFactor, SortFactor, bool, Set<CollectionFilter>, Set<CollectionFilter>)>(
            selector: (context, s) => (s.albumSectionFactor, s.albumSortFactor, s.albumSortReverse, s.hiddenFilters, s.pinnedFilters),
            shouldRebuild: (t1, t2) {
              // `Selector` by default uses `DeepCollectionEquality`, which does not go deep in collections within records
              const eq = DeepCollectionEquality();
              return !(eq.equals(t1.$1, t2.$1) && eq.equals(t1.$2, t2.$2) && eq.equals(t1.$3, t2.$3) && eq.equals(t1.$4, t2.$4) && eq.equals(t1.$5, t2.$5));
            },
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
                        final gridItems = getGridItems(context, source, AlbumChipType.values.toSet(), groupUri);
                        return StreamBuilder<Set<CollectionFilter>?>(
                          // to update sections by tier
                          stream: covers.packageChangeStream,
                          builder: (context, _) => FilterNavigationPage<AlbumBaseFilter, AlbumChipSetActionDelegate>(
                            source: source,
                            title: context.l10n.albumPageTitle,
                            sortFactor: settings.albumSortFactor,
                            showHeaders: settings.albumSectionFactor != ChipSectionFactor.none,
                            actionDelegate: AlbumChipSetActionDelegate(gridItems),
                            filterSections: groupToSections(context, source, gridItems),
                            newFilters: source.getNewAlbumFilters(context),
                            emptyBuilder: () => EmptyContent(
                              icon: AIcons.album,
                              text: context.l10n.albumEmpty,
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
    );
  }

  // common with picking page

  static List<FilterGridItem<AlbumBaseFilter>> getGridItems(
    BuildContext context,
    CollectionSource source,
    Set<AlbumChipType> albumChipTypes,
    Uri? groupUri,
  ) {
    final groupContent = albumGrouping.getDirectChildren(groupUri);

    Set<T> whereTypeRecursively<T>(Set<CollectionFilter> filters) {
      return {
        ...filters.whereType<T>(),
        ...filters.whereType<AlbumGroupFilter>().expand((v) => whereTypeRecursively<T>(v.filter.innerFilters)),
      };
    }

    // show hidden filters when they are pinned
    final pinned = settings.pinnedFilters.whereType<AlbumBaseFilter>();
    final hidden = settings.hiddenFilters.whereNot(pinned.contains).toSet();

    final listedStoredAlbumPaths = <String>{};
    if (albumChipTypes.contains(AlbumChipType.stored)) {
      final allAlbums = source.rawAlbums;
      if (groupUri == null) {
        final withinGroups = whereTypeRecursively<StoredAlbumFilter>(groupContent).map((v) => v.album).toSet();
        listedStoredAlbumPaths.addAll(allAlbums.whereNot(withinGroups.contains));
      } else {
        // check that group content is listed from source, to prevent displaying hidden content
        listedStoredAlbumPaths.addAll(groupContent.whereType<StoredAlbumFilter>().map((v) => v.album).where(allAlbums.contains));
      }
    }
    final listedStoredAlbums = listedStoredAlbumPaths.map((album) => StoredAlbumFilter(album, source.getStoredAlbumDisplayName(context, album))).whereNot(hidden.contains).toSet();

    final listedDynamicAlbums = <DynamicAlbumFilter>{};
    if (albumChipTypes.contains(AlbumChipType.dynamic)) {
      final allDynamicAlbums = dynamicAlbums.all.whereNot(hidden.contains).toSet();
      if (groupUri == null) {
        final withinGroups = whereTypeRecursively<DynamicAlbumFilter>(groupContent).toSet();
        listedDynamicAlbums.addAll(allDynamicAlbums.whereNot(withinGroups.contains));
      } else {
        // check that group content is listed from source, to prevent displaying hidden content
        listedDynamicAlbums.addAll(groupContent.whereType<DynamicAlbumFilter>().where(allDynamicAlbums.contains));
      }
    }

    // always show groups, which are needed to navigate to other types
    final albumGroupFilters = groupContent.whereType<AlbumGroupFilter>().whereNot(hidden.contains).toSet();

    final filters = <AlbumBaseFilter>{
      ...albumGroupFilters,
      ...listedStoredAlbums,
      ...listedDynamicAlbums,
    };

    return FilterNavigationPage.sort(settings.albumSortFactor, settings.albumSortReverse, source, filters);
  }

  static Map<ChipSectionKey, List<FilterGridItem<AlbumBaseFilter>>> groupToSections(BuildContext context, CollectionSource source, Iterable<FilterGridItem<AlbumBaseFilter>> sortedMapEntries) {
    final newFilters = source.getNewAlbumFilters(context);
    final pinned = settings.pinnedFilters.whereType<AlbumBaseFilter>();

    final List<FilterGridItem<AlbumBaseFilter>> newMapEntries = [], pinnedMapEntries = [], unpinnedMapEntries = [];
    for (final item in sortedMapEntries) {
      final filter = item.filter;
      if (newFilters.contains(filter)) {
        newMapEntries.add(item);
      } else if (pinned.contains(filter)) {
        pinnedMapEntries.add(item);
      } else {
        unpinnedMapEntries.add(item);
      }
    }

    var sections = <ChipSectionKey, List<FilterGridItem<AlbumBaseFilter>>>{};
    switch (settings.albumSectionFactor) {
      case .importance:
        final groupKey = ChipImportanceSectionKey.group(context);
        final specialKey = ChipImportanceSectionKey.special(context);
        final appsKey = ChipImportanceSectionKey.apps(context);
        final vaultKey = ChipImportanceSectionKey.vault(context);
        final dynamicKey = ChipImportanceSectionKey.dynamic(context);
        final regularKey = ChipImportanceSectionKey.regular(context, AIcons.album);
        sections = groupBy<FilterGridItem<AlbumBaseFilter>, ChipSectionKey>(unpinnedMapEntries, (kv) {
          final filter = kv.filter;
          switch (filter) {
            case AlbumGroupFilter _:
              return groupKey;
            case DynamicAlbumFilter _:
              return dynamicKey;
            case StoredAlbumFilter _:
              switch (covers.effectiveAlbumType(filter.album)) {
                case .regular:
                  return regularKey;
                case .app:
                  return appsKey;
                case .vault:
                  return vaultKey;
                default:
                  return specialKey;
              }
            default:
              return specialKey;
          }
        });

        sections = {
          // group ordering
          if (sections.containsKey(groupKey)) groupKey: sections[groupKey]!,
          if (sections.containsKey(specialKey)) specialKey: sections[specialKey]!,
          if (sections.containsKey(appsKey)) appsKey: sections[appsKey]!,
          if (sections.containsKey(vaultKey)) vaultKey: sections[vaultKey]!,
          if (sections.containsKey(dynamicKey)) dynamicKey: sections[dynamicKey]!,
          if (sections.containsKey(regularKey)) regularKey: sections[regularKey]!,
        };
      case .mimeType:
        // A windowed source holds no entries: each album's media kinds come from
        // the summary domain, which aggregates them from the database.
        final visibleEntries = source.visibleEntries;
        final summaries = visibleEntries.isEmpty ? source.summaries : null;
        sections = groupBy<FilterGridItem<AlbumBaseFilter>, ChipSectionKey>(unpinnedMapEntries, (kv) {
          final kinds = summaries != null ? summaries.albumMediaKinds(kv.filter) : _mediaKinds(visibleEntries, kv.filter);
          if (kinds.hasImage && !kinds.hasVideo) return MimeTypeSectionKey.images(context);
          if (!kinds.hasImage && kinds.hasVideo) return MimeTypeSectionKey.videos(context);
          return MimeTypeSectionKey.mixed(context);
        });
      case .volume:
        sections = groupBy<FilterGridItem<AlbumBaseFilter>, ChipSectionKey>(unpinnedMapEntries, (kv) {
          final filter = kv.filter;
          return StorageVolumeSectionKey(context, filter is StoredAlbumFilter ? filter.storageVolume : null);
        });
      case .none:
        return {
          if (sortedMapEntries.isNotEmpty)
            const ChipSectionKey(): [
              ...newMapEntries,
              ...pinnedMapEntries,
              ...unpinnedMapEntries,
            ],
        };
    }

    if (pinnedMapEntries.isNotEmpty) {
      sections = Map.fromEntries([
        MapEntry(ChipImportanceSectionKey.pinned(context), pinnedMapEntries),
        ...sections.entries,
      ]);
    }

    if (newMapEntries.isNotEmpty) {
      sections = Map.fromEntries([
        MapEntry(ChipImportanceSectionKey.newAlbum(context), newMapEntries),
        ...sections.entries,
      ]);
    }

    return sections;
  }

  /// The media kinds of an album's entries, as the in-memory grouping reads them.
  static ({bool hasImage, bool hasVideo}) _mediaKinds(Iterable<AvesEntry> entries, AlbumBaseFilter filter) {
    final matches = entries.where(filter.test);
    return (hasImage: matches.any((v) => v.isImage), hasVideo: matches.any((v) => v.isVideo));
  }
}
