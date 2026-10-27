import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_action_delegate.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_section_key.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_tile.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_apply.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart' show VisibleRangeActiveStyle;
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_active_footer.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/scaling.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/tile_extent_controller.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The wallpaper-group page: the visible-range editor with a group switcher on
/// top.
///
/// It reuses the range page's sections, tiles and active footer, but edits the
/// range of the selected wallpaper group (`scope = wallpaper`) instead of the
/// gallery's single range. Its layout, title query, active-style form and group
/// switcher are stored under this page's own keys, so the two pages can look
/// different.
///
/// [routeName] is a settings key only: the page shares the visible-range
/// destination in the bottom bar and is rendered by [VisibleRangeShellPage].
class GroupedWallpaperPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups';

  const new({super.key});

  @override
  State<GroupedWallpaperPage> createState() => _GroupedWallpaperPageState();
}

enum _PageAction {
  useCurrent,
  toggleEnabled,
  moveUp,
  moveDown,
  rename,
  add,
  delete,
  order,
  lock,
  about,
  applyToMediaSet,
  deleteSelectedRules,
  visibleRange,
}

class _GroupedWallpaperPageState extends State<GroupedWallpaperPage> {
  /// Width of one card of the fixed five-column switcher.
  static const int _grid5ColumnCount = 5;

  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  Map<String, Set<CollectionFilter>> _groupFilters = const {};
  VisibleRangeCandidateStats? _resultStats;
  int _resultToken = 0;

  late final WallpaperGroupRangeController _controller;

  /// The page's multi-selection.
  ///
  /// The page owns it instead of looking it up in the widget tree: the handlers
  /// below run from the `State`'s context, which sits above the provider created
  /// in `build`, so an ancestor lookup would never find it. Holding the instance
  /// also states who is responsible for disposing it.
  ///
  /// `toSelectableItems` is passed explicitly because the model requires the
  /// choice: a grid item is selected as itself.
  final _selection = Selection<FilterGridItem<CollectionFilter>>(toSelectableItems: null);

  /// The group the current selection was made in.
  String? _selectionGroupId;

  @override
  void initState() {
    super.initState();
    _controller = WallpaperGroupRangeController();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.init());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _selection.dispose();
    _appBarHeightNotifier.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // A selection only means something inside the group it was made in: the
    // actions below write to the selected group's range, so carrying candidates
    // over to another group would apply or delete them in the wrong place.
    final groupId = _controller.selectedGroupId;
    if (groupId != _selectionGroupId) {
      _selectionGroupId = groupId;
      _selection.browse();
    }
    setState(() {});
    unawaited(_refreshResultStats());
    unawaited(_refreshGroupFilters());
  }

  /// Count and cover of what the selected group's range resolves to.
  Future<void> _refreshResultStats() async {
    final range = _controller.range;
    final token = ++_resultToken;
    if (range == null) {
      setState(() => _resultStats = null);
      return;
    }
    final filter = range.resolve();
    final filters = filter == null ? const <CollectionFilter>{} : <CollectionFilter>{filter};
    final stats = await VisibleRangeCandidateStatsLoader.load([filters]);
    if (!mounted || token != _resultToken) return;
    setState(() => _resultStats = stats.values.firstOrNull);
  }

  /// The media set behind every group card, so a card without a note can show
  /// its image count. Group 0 is every image.
  Future<void> _refreshGroupFilters() async {
    final next = <String, Set<CollectionFilter>>{wallpaperGroupNoneId: {MimeFilter.image}};
    for (final group in _controller.groups) {
      final range = await _controller.groupController.groupRange(group.id);
      final filter = wallpaperMediaSetFilter(range);
      next[group.id] = filter == null ? {MimeFilter.image} : {filter};
    }
    if (!mounted) return;
    setState(() => _groupFilters = next);
    await _refreshStats();
  }

  Future<void> _refreshStats() async {
    final range = _controller.range;
    final filtersByKey = <String, Set<CollectionFilter>>{};
    if (range != null) {
      for (final section in buildVisibleRangeSections(range: range, presets: _controller.presets)) {
        for (final candidate in section.candidates) {
          filtersByKey.putIfAbsent(candidate.statsKey, () => candidate.filters);
        }
      }
    }
    for (final filters in _groupFilters.values) {
      filtersByKey.putIfAbsent(filterFingerprint(filters), () => filters);
    }
    final missing = filtersByKey.entries
        .where((entry) => !_stats.containsKey(entry.key) && !_pendingStats.contains(entry.key))
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList();
    if (missing.isEmpty) return;
    _pendingStats.addAll(missing.map((entry) => entry.key));
    try {
      await VisibleRangeCandidateStatsLoader.load(
        missing.map((entry) => entry.value),
        onResult: (key, stats) {
          if (!mounted) return;
          setState(() => _stats = {..._stats, key: stats});
        },
      );
    } finally {
      _pendingStats.removeAll(missing.map((entry) => entry.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final source = context.read<CollectionSource>();
        final sections = _buildSections(context);
        final delegate = WallpaperGroupActionDelegate(
          settingsRouteKey: GroupedWallpaperPage.routeName,
          // Only applicable candidates take part in the selection: the result
          // preview and the unrestricted base are shown but cannot be selected,
          // so a "select all" must not pick them up either.
          itemBuilder: () => sections.values.expand((list) => list).where((item) {
            final filter = item.filter;
            return filter is VisibleRangeCandidateFilter && !filter.summary && filter.candidate.isApplicable;
          }).toList(),
          // The page keeps its own view preferences, so the layout dialog shows
          // the same controls as the visible-range page but writes this page's
          // keys.
          extraLayoutRows: (context) => [_buildActiveStyleRow(context), _buildSwitcherStyleRow(context)],
        );
        return FilterGroupProvider(
          child: ChangeNotifierProvider<Selection<FilterGridItem<CollectionFilter>>>.value(
            value: _selection,
            child: Builder(
              builder: (context) {
                final scrollController = PrimaryScrollController.of(context);
                return QueryProvider(
                  startEnabled: settings.getShowTitleQuery(GroupedWallpaperPage.routeName),
                  child: FilterGridPage<CollectionFilter>(
                    settingsRouteKey: GroupedWallpaperPage.routeName,
                    appBar: FilterGridAppBar<CollectionFilter, WallpaperGroupActionDelegate>(
                      source: source,
                      title: context.l10n.wallpaperGroupsTitle,
                      titleStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0,
                        fontFeatures: const [],
                      ),
                      actionDelegate: delegate,
                      extraActionsBuilder: _buildExtraActions,
                      extraMenuEntriesBuilder: _buildExtraMenuEntries,
                      onExtraMenuSelected: (value) {
                        if (value is _PageAction) unawaited(_onMenuSelected(value));
                      },
                      appBarHeightNotifier: _appBarHeightNotifier,
                      scrollController: scrollController,
                      onGroupCrumbTap: (context, filter) {},
                    ),
                    appBarHeightNotifier: _appBarHeightNotifier,
                    scrollController: scrollController,
                    sections: sections,
                    newFilters: const {},
                    sortFactor: delegate.sortFactor,
                    showHeaders: true,
                    selectable: true,
                    // The section mode already lays the groups out in the grid.
                    headerBuilder: _controller.switcherStyle == WallpaperGroupSwitcherStyle.sections ? null : _buildGroupSwitcher,
                    emptyBuilder: _buildEmpty,
                    heroType: HeroType.never,
                    onTileTap: (item, navigate) => _onTileTap(item),
                    selectableItem: (item) {
                      final filter = item.filter;
                      return filter is VisibleRangeCandidateFilter && !filter.summary && filter.candidate.isApplicable;
                    },
                    tileBuilder: _buildTile,
                    footerBuilder: _controller.activeStyle == VisibleRangeActiveStyle.section ? null : _buildFooter,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    final l10n = context.l10n;
    if (_controller.loading) return const Center(child: CircularProgressIndicator());
    if (_controller.groups.isEmpty) return Center(child: Text(l10n.wallpaperGroupsEmpty));
    if (_controller.selectedGroupId == null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l10n.wallpaperGroupNoneBody, textAlign: TextAlign.center)));
    return Center(child: Text(l10n.visibleRangeNoCandidates));
  }

  // group switcher

  /// The switcher pinned above the sections in the chips and five-column modes.
  ///
  /// It selects which group's range is shown; it never changes the wallpaper's
  /// current group, which is a group action and belongs to the group menu.
  Widget _buildGroupSwitcher(BuildContext context) {
    switch (_controller.switcherStyle) {
      case WallpaperGroupSwitcherStyle.chips:
        return _buildGroupChips(context);
      case WallpaperGroupSwitcherStyle.grid5:
        return _buildGroupGrid5(context);
      case WallpaperGroupSwitcherStyle.sections:
        return const SizedBox();
    }
  }

  Widget _buildGroupChips(BuildContext context) {
    final l10n = context.l10n;
    final selected = _controller.selectedGroupId;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(l10n.wallpaperGroupNone),
              selected: selected == null,
              onSelected: (_) => unawaited(_controller.selectGroup(null)),
            ),
          ),
          for (final group in _controller.groups)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Tooltip(
                // The chips mode has no room for a subtitle, so the note reads
                // as a tooltip instead.
                message: group.description,
                child: ChoiceChip(
                  avatar: _groupStateIcon(context, group),
                  label: Text('${group.number}  ${wallpaperGroupName(context, group)}'),
                  selected: selected == group.id,
                  labelStyle: group.enabled ? null : TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onSelected: (_) => unawaited(_controller.selectGroup(group.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupGrid5(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        const padding = 12.0;
        final width = (constraints.maxWidth - padding * 2 - spacing * (_grid5ColumnCount - 1)) / _grid5ColumnCount;
        final height = width * 1.25;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 8),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final groupId in _groupFilters.keys)
                SizedBox(
                  width: width,
                  height: height,
                  child: WallpaperGroupTile(
                    filter: _buildGroupFilter(groupId),
                    tileLayout: TileLayout.grid,
                    tileSize: Size(width, height),
                    onTap: () => unawaited(_controller.selectGroup(groupId == wallpaperGroupNoneId ? null : groupId)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget? _groupStateIcon(BuildContext context, WallpaperGroup group) {
    final selected = _controller.selectedGroupId == group.id;
    if (!group.current && !selected) return null;
    return Icon(
      group.current ? AIcons.wallpaperPlaying : AIcons.visibleRangeActive,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  WallpaperGroupFilter _buildGroupFilter(String groupId) {
    final group = groupId == wallpaperGroupNoneId ? null : _controller.groups.firstWhereOrNull((candidate) => candidate.id == groupId);
    final filters = _groupFilters[groupId];
    return WallpaperGroupFilter(
      groupId: group?.id,
      number: group?.number ?? 0,
      name: group?.name ?? '@wallpaperGroupNone',
      description: group?.description ?? '',
      enabled: group?.enabled ?? true,
      current: group == null ? _controller.current.isNone : group.current,
      selected: _controller.selectedGroupId == group?.id,
      count: filters == null ? null : _stats[filterFingerprint(filters)]?.count,
    );
  }

  // sections

  Map<ChipSectionKey, List<FilterGridItem<CollectionFilter>>> _buildSections(BuildContext context) {
    final result = <ChipSectionKey, List<FilterGridItem<CollectionFilter>>>{};
    if (_controller.switcherStyle == WallpaperGroupSwitcherStyle.sections) {
      result[WallpaperGroupSectionKey(context)] = [
        for (final groupId in _groupFilters.keys) FilterGridItem<CollectionFilter>(_buildGroupFilter(groupId), null),
      ];
    }
    final range = _controller.range;
    if (range == null) return result;
    final supplementsOutside = range.order.isIntersectFirst;
    for (final section in buildVisibleRangeSections(range: range, presets: _controller.presets)) {
      // A wallpaper group starts with its exclusive base and nothing else, so an
      // empty restrictions/supplements group would only be a title reading 0/0.
      if (section.kind != VisibleRangeCandidateKind.base && section.candidates.isEmpty) continue;
      // Wallpaper uses images only: a video-only base is not a choice here. An
      // already selected one stays visible, otherwise the base would read as
      // unselected while the range still carries it.
      final candidates = section.kind == VisibleRangeCandidateKind.base
          ? [
              for (final candidate in section.candidates)
                if (candidate.active || candidate.preset == null || !isVideoOnlyFilterSet(candidate.preset!.filters)) candidate,
            ]
          : section.candidates;
      final countText = switch (section.kind) {
        VisibleRangeCandidateKind.base => '${candidates.length}',
        VisibleRangeCandidateKind.restriction || VisibleRangeCandidateKind.supplement => '${candidates.where((candidate) => candidate.active).length}/${candidates.length}',
      };
      final key = VisibleRangeSectionKey(context, section.kind, countText: countText, supplementsOutside: supplementsOutside);
      final ordered = section.kind == VisibleRangeCandidateKind.base
          ? [...candidates.where((candidate) => candidate.isUnrestricted), ...candidates.where((candidate) => !candidate.isUnrestricted)]
          : candidates;
      result[key] = [
        for (final candidate in ordered) FilterGridItem<CollectionFilter>(VisibleRangeCandidateFilter(candidate), null),
      ];
    }
    if (_controller.activeStyle == VisibleRangeActiveStyle.section) {
      final active = buildVisibleRangeActiveCandidates(range: range, presets: _controller.presets);
      result[VisibleRangeActiveSectionKey(context, restricted: range.isRestricted)] = [
        for (final candidate in active) FilterGridItem<CollectionFilter>(VisibleRangeCandidateFilter(candidate, summary: true), null),
      ];
    }
    return result;
  }

  Widget _buildTile(BuildContext context, FilterGridItem<CollectionFilter> item, Size tileSize) {
    final filter = item.filter;
    if (filter is WallpaperGroupFilter) {
      return MetaData(
        metaData: ScalerMetadata(item),
        child: WallpaperGroupTile(
          filter: filter,
          tileLayout: settings.getTileLayout(GroupedWallpaperPage.routeName),
          tileSize: tileSize,
          onTap: () => unawaited(_controller.selectGroup(filter.groupId)),
        ),
      );
    }
    final candidateFilter = filter as VisibleRangeCandidateFilter;
    final candidate = candidateFilter.candidate;
    return MetaData(
      metaData: ScalerMetadata(item),
      child: ListenableBuilder(
        listenable: _selection,
        builder: (context, _) => VisibleRangeTile(
          gridItem: FilterGridItem(candidateFilter, item.entry),
          stats: candidate.isGallery ? _resultStats : _stats[candidate.statsKey],
          tileLayout: settings.getTileLayout(GroupedWallpaperPage.routeName),
          tileSize: tileSize,
          summary: candidateFilter.summary,
          showStateIcon: !candidate.isGallery,
          selectable: !candidateFilter.summary && candidate.isApplicable,
          selecting: _selection.isSelecting,
          selected: _selection.selectedItems.contains(item),
          onTap: () => _onTileTap(item),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final range = _controller.range;
    if (range == null) return const SizedBox();
    final baseCandidates = buildVisibleRangeSections(range: range, presets: _controller.presets).first.candidates;
    final activeBase = baseCandidates.firstWhereOrNull((candidate) => candidate.active);
    final activeRules = [
      for (final kind in range.order.isIntersectFirst
          ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement]
          : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
        for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
    ];
    return VisibleRangeActiveFooter(
      range: range,
      activeBase: activeBase,
      activeRules: activeRules,
      style: _controller.activeStyle,
      resultStats: _resultStats,
      statsFor: (candidate) => _stats[candidate.statsKey],
      tileExtent: context.select<TileExtentController, double>((controller) => controller.extentNotifier.value),
      onCancelBase: _cancelBase,
      onCancelRule: (candidate) {
        final rule = candidate.rule;
        if (rule != null) _toggleRule(rule);
      },
      onAbout: _openAbout,
    );
  }

  void _toggleRule(VisibleRangeRule rule) {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    unawaited(_controller.toggleRule(rule.id));
  }

  void _cancelBase() {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    unawaited(_controller.clearBase());
  }

  Future<void> _openAbout() => Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: VisibleRangeAboutPage.routeName),
          builder: (_) => const VisibleRangeAboutPage(wallpaperFirst: true),
        ),
      );

  void _onTileTap(FilterGridItem<CollectionFilter> item) {
    final filter = item.filter;
    if (filter is WallpaperGroupFilter) {
      unawaited(_controller.selectGroup(filter.groupId));
      return;
    }
    final candidateFilter = filter as VisibleRangeCandidateFilter;
    final candidate = candidateFilter.candidate;
    if (_controller.selectedGroupId == null) return;
    if (_selection.isSelecting) {
      if (candidate.isApplicable) _selection.toggleSelection(item);
      return;
    }
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    if (candidateFilter.summary) {
      final rule = candidate.rule;
      if (rule != null) {
        unawaited(_controller.toggleRule(rule.id));
      } else if (!candidate.isGallery && !candidate.isUnrestricted) {
        unawaited(_controller.clearBase());
      }
      return;
    }
    switch (candidate.kind) {
      case VisibleRangeCandidateKind.base:
        if (candidate.isUnrestricted) {
          unawaited(_controller.clearBase());
        } else if (candidate.preset != null) {
          final preset = candidate.preset!;
          unawaited(_controller.selectBase(presetId: preset.id, name: preset.name, filters: preset.filters));
        }
      case VisibleRangeCandidateKind.restriction:
      case VisibleRangeCandidateKind.supplement:
        final rule = candidate.rule;
        if (rule != null) unawaited(_controller.toggleRule(rule.id));
    }
  }

  // view preferences

  Widget _buildActiveStyleRow(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AIcons.visibleRangeActive),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.visibleRangeActiveStyle)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<VisibleRangeActiveStyle>(
              segments: [
                ButtonSegment(value: VisibleRangeActiveStyle.section, label: Text(l10n.visibleRangeActiveStyleSection)),
                ButtonSegment(value: VisibleRangeActiveStyle.compactChips, label: Text(l10n.visibleRangeActiveStyleChips)),
                ButtonSegment(value: VisibleRangeActiveStyle.tiles, label: Text(l10n.visibleRangeActiveStyleTiles)),
              ],
              selected: {_controller.activeStyle},
              onSelectionChanged: (selection) => unawaited(_controller.setActiveStyle(selection.first)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitcherStyleRow(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AIcons.wallpaper),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.wallpaperGroupSwitcherStyle)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<WallpaperGroupSwitcherStyle>(
              segments: [
                ButtonSegment(value: WallpaperGroupSwitcherStyle.chips, label: Text(l10n.wallpaperGroupSwitcherChips)),
                ButtonSegment(value: WallpaperGroupSwitcherStyle.sections, label: Text(l10n.wallpaperGroupSwitcherSections)),
                ButtonSegment(value: WallpaperGroupSwitcherStyle.grid5, label: Text(l10n.wallpaperGroupSwitcherGrid5)),
              ],
              selected: {_controller.switcherStyle},
              onSelectionChanged: (selection) => unawaited(_controller.setSwitcherStyle(selection.first)),
            ),
          ],
        ),
      ),
    );
  }

  // app bar

  /// The TV rail has no overflow menu, so the selection actions stay reachable
  /// as icons, mirroring the visible-range page.
  List<Widget> _buildExtraActions(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<CollectionFilter>> selection,
    WallpaperGroupActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      if (!settings.useTvLayout) return const [];
      final hasSelection = selection.selectedItemCount > 0;
      final hasRules = _selectedRules(selection).isNotEmpty;
      return [
        if (hasSelection)
          IconButton(
            icon: const Icon(AIcons.apply),
            tooltip: context.l10n.visibleRangeApplyToMediaSet,
            onPressed: () => unawaited(_applySelectionToMediaSet()),
          ),
        if (hasRules)
          IconButton(
            icon: const Icon(AIcons.delete),
            tooltip: context.l10n.visibleRangeActionDelete,
            onPressed: () => unawaited(_deleteSelectedRules()),
          ),
      ];
    }
    if (!settings.useTvLayout) return const [];
    return [
      PopupMenuButton<_PageAction>(
        icon: const Icon(AIcons.more),
        tooltip: context.l10n.visibleRangeMore,
        onSelected: (action) => unawaited(_onMenuSelected(action)),
        itemBuilder: _menuEntries,
      ),
    ];
  }

  /// Feature entries injected into the app bar's single overflow menu.
  List<PopupMenuEntry<Object>> _buildExtraMenuEntries(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<CollectionFilter>> selection,
    WallpaperGroupActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      final hasSelection = selection.selectedItemCount > 0;
      final hasRules = _selectedRules(selection).isNotEmpty;
      return [
        if (hasSelection) _menuItem(_PageAction.applyToMediaSet, AIcons.apply, context.l10n.visibleRangeApplyToMediaSet),
        if (hasRules) _menuItem(_PageAction.deleteSelectedRules, AIcons.delete, context.l10n.visibleRangeActionDelete),
      ];
    }
    return _menuEntries(context);
  }

  Set<VisibleRangeRule> _selectedRules(Selection<FilterGridItem<CollectionFilter>> selection) {
    if (!selection.isSelecting) return {};
    return selection.selectedItems.map((item) => (item.filter as VisibleRangeCandidateFilter?)?.candidate.rule).nonNulls.toSet();
  }

  /// Takes the selected candidates out to the media set, exactly like the
  /// visible-range page: the union of their filters is appended and every
  /// target is remembered for the pin sheet's write-back list.
  Future<void> _applySelectionToMediaSet() async {
    final range = _controller.range;
    if (!_selection.isSelecting || range == null) return;
    final candidates = [
      for (final item in _selection.selectedItems)
        if (item.filter is VisibleRangeCandidateFilter) (item.filter as VisibleRangeCandidateFilter).candidate,
    ];
    if (candidates.isEmpty) return;
    _selection.browse();
    await applyVisibleRangeCandidates(context, rangeId: range.id, candidates: candidates);
  }

  Future<void> _deleteSelectedRules() async {
    final rules = _selectedRules(_selection);
    if (rules.isEmpty) return;
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    _selection.browse();
    await _controller.deleteRules(rules.map((rule) => rule.id).toSet());
  }

  List<PopupMenuEntry<_PageAction>> _menuEntries(BuildContext context) {
    final l10n = context.l10n;
    final group = _selectedGroup;
    final range = _controller.range;
    final locked = range?.locked ?? false;
    final canDelete = _controller.groups.length > 1;
    return [
      // The wallpaper page shares one bottom-bar entry with the visible-range
      // page; this switches the shared destination for the rest of the process.
      _menuItem(_PageAction.visibleRange, AIcons.visibleRange, l10n.visibleRangePageTitle),
      const PopupMenuDivider(),
      if (group == null)
        // Group 0 is the explicit "no group effect" choice.
        _menuItem(_PageAction.useCurrent, AIcons.current, l10n.wallpaperGroupNone)
      else ...[
        if (!group.current && group.enabled) _menuItem(_PageAction.useCurrent, AIcons.current, l10n.wallpaperGroupUseCurrent),
        _menuItem(
          _PageAction.toggleEnabled,
          group.enabled ? AIcons.unselected : AIcons.checked,
          group.enabled ? l10n.wallpaperGroupDisable : l10n.wallpaperGroupEnable,
        ),
        _menuItem(_PageAction.moveUp, AIcons.up, l10n.wallpaperGroupMoveUp),
        _menuItem(_PageAction.moveDown, AIcons.down, l10n.wallpaperGroupMoveDown),
        const PopupMenuDivider(),
        _menuItem(_PageAction.rename, AIcons.edit, l10n.wallpaperGroupRename),
      ],
      _menuItem(_PageAction.add, AIcons.add, l10n.wallpaperGroupAdd),
      if (group != null) _menuItem(_PageAction.delete, AIcons.delete, l10n.wallpaperGroupDelete, enabled: canDelete),
      const PopupMenuDivider(),
      if (range != null) ...[
        _menuItem(_PageAction.order, AIcons.sortOrder, l10n.visibleRangeOrder),
        _menuItem(_PageAction.lock, locked ? AIcons.locked : AIcons.unlocked, locked ? l10n.visibleRangeUnlock : l10n.visibleRangeLock),
        const PopupMenuDivider(),
      ],
      _menuItem(_PageAction.about, AIcons.info, l10n.aboutWallpaperTitle),
    ];
  }

  PopupMenuItem<_PageAction> _menuItem(_PageAction value, IconData icon, String text, {bool enabled = true}) => PopupMenuItem<_PageAction>(
        value: value,
        enabled: enabled,
        child: _menuRow(icon, text),
      );

  Widget _menuRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ],
    );
  }

  WallpaperGroup? get _selectedGroup {
    final id = _controller.selectedGroupId;
    if (id == null) return null;
    return _controller.groups.firstWhereOrNull((group) => group.id == id);
  }

  Future<void> _onMenuSelected(_PageAction action) async {
    final group = _selectedGroup;
    switch (action) {
      case _PageAction.visibleRange:
        visibleRangeDestination.value = VisibleRangeDestination.range;
      case _PageAction.useCurrent:
        await _controller.selectCurrent(group?.id);
      case _PageAction.toggleEnabled:
        if (group != null) await _controller.setEnabled(group.id, !group.enabled);
      case _PageAction.moveUp:
        if (group != null) await _controller.moveGroup(group.id, -1);
      case _PageAction.moveDown:
        if (group != null) await _controller.moveGroup(group.id, 1);
      case _PageAction.rename:
        if (group != null) await _renameGroup(group);
      case _PageAction.add:
        await _addGroup();
      case _PageAction.delete:
        if (group != null) await _deleteGroup(group);
      case _PageAction.order:
        await _pickOrder();
      case _PageAction.lock:
        await _toggleLock();
      case _PageAction.about:
        await _openAbout();
      case _PageAction.applyToMediaSet:
        await _applySelectionToMediaSet();
      case _PageAction.deleteSelectedRules:
        await _deleteSelectedRules();
    }
  }

  Future<void> _renameGroup(WallpaperGroup group) async {
    final result = await _askGroupTexts(
      title: context.l10n.wallpaperGroupNameTitle,
      initialName: group.hasBundledName ? '' : group.name,
      nameHint: wallpaperGroupName(context, group),
      initialDescription: group.description,
    );
    if (result == null) return;
    await _controller.updateGroup(group.id, name: result.name, description: result.description);
  }

  Future<void> _addGroup() async {
    final result = await _askGroupTexts(
      title: context.l10n.wallpaperGroupAdd,
      initialName: '',
      // A new group's note defaults to the moment it was created, which is what
      // the card subtitle shows until the user writes something else.
      initialDescription: formatDateTime(DateTime.now(), settings.avesLocale, MediaQuery.alwaysUse24HourFormatOf(context)),
    );
    // An empty name is allowed: the group keeps its derived number until the
    // user names it.
    if (result == null) return;
    await _controller.addGroup(name: result.name, description: result.description);
  }

  Future<({String name, String description})?> _askGroupTexts({
    required String title,
    required String initialName,
    required String initialDescription,
    String? nameHint,
  }) async {
    final l10n = context.l10n;
    final nameController = TextEditingController(text: initialName);
    final descriptionController = TextEditingController(text: initialDescription);
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.visibleRangePinName, hintText: nameHint),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.visibleRangePinDescription),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(
            onPressed: () => Navigator.pop(context, (name: nameController.text.trim(), description: descriptionController.text.trim())),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    return result;
  }

  Future<void> _deleteGroup(WallpaperGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.wallpaperGroupDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await _controller.deleteGroup(group.id);
    if (!mounted || deleted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperGroupKeepOne)));
  }

  Future<void> _pickOrder() async {
    final l10n = context.l10n;
    final current = _controller.range?.order;
    final order = await showDialog<VisibleRangeOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.visibleRangeOrder),
        children: [
          _orderTile(context, title: l10n.visibleRangeOrderIntersectFirst, value: VisibleRangeOrder.intersectFirst, current: current),
          _orderTile(context, title: l10n.visibleRangeOrderUnionFirst, value: VisibleRangeOrder.unionFirst, current: current),
        ],
      ),
    );
    if (order == null) return;
    await _controller.setOrder(order);
  }

  Widget _orderTile(BuildContext context, {required String title, required VisibleRangeOrder value, required VisibleRangeOrder? current}) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(current == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(title)),
        ],
      ),
    );
  }

  Future<void> _toggleLock() async {
    final range = _controller.range;
    if (range == null) return;
    if (range.locked) {
      await _controller.unlock();
      return;
    }
    await _controller.lockWithPreset(VisibleRangeLockPreset.readOnly);
  }

  void _showBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeManagementBlocked)));
  }
}
