import 'dart:async';

import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_action_delegate.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart' show VisibleRangeActiveStyle;
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_active_footer.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/scaling.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:aves/widgets/common/tile_extent_controller.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The wallpaper-group page: the visible-range editor with a group switcher on
/// top.
///
/// It reuses the range page's sections, tiles and active footer, but edits the
/// range of the selected wallpaper group (`scope = wallpaper`) instead of the
/// gallery's single range. Its layout, title query and active-style form are
/// stored under this page's own keys, so the two pages can look different.
class GroupedWallpaperPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups';

  const new({super.key});

  @override
  State<GroupedWallpaperPage> createState() => _GroupedWallpaperPageState();
}

enum _PageAction { order, lock, about }

class _GroupedWallpaperPageState extends State<GroupedWallpaperPage> {
  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  VisibleRangeCandidateStats? _resultStats;
  int _resultToken = 0;

  late final WallpaperGroupRangeController _controller;

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
    _appBarHeightNotifier.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshResultStats());
    unawaited(_refreshStats());
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

  Future<void> _refreshStats() async {
    final range = _controller.range;
    if (range == null) return;
    final filtersByKey = <String, Set<CollectionFilter>>{};
    for (final section in buildVisibleRangeSections(range: range, presets: _controller.presets)) {
      for (final candidate in section.candidates) {
        filtersByKey.putIfAbsent(candidate.statsKey, () => candidate.filters);
      }
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
          itemBuilder: () => sections.values.expand((list) => list).where((item) => !item.filter.summary).toList(),
          // The page keeps its own active-style form, so the layout dialog shows
          // the same control as the visible-range page but writes this page's key.
          extraLayoutRows: (context) => [_buildActiveStyleRow(context)],
        );
        return FilterGroupProvider(
          child: SelectionProvider<FilterGridItem<VisibleRangeCandidateFilter>>(
            child: Builder(
              builder: (context) {
                final scrollController = PrimaryScrollController.of(context);
                return QueryProvider(
                  startEnabled: settings.getShowTitleQuery(GroupedWallpaperPage.routeName),
                  child: FilterGridPage<VisibleRangeCandidateFilter>(
                    settingsRouteKey: GroupedWallpaperPage.routeName,
                    appBar: FilterGridAppBar<VisibleRangeCandidateFilter, WallpaperGroupActionDelegate>(
                      source: source,
                      title: context.l10n.wallpaperGroupsTitle,
                      titleStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0,
                        fontFeatures: const [],
                      ),
                      actionDelegate: delegate,
                      extraMenuEntriesBuilder: (context, appMode, selection, actionDelegate) => _menuEntries(context),
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
                    selectable: false,
                    headerBuilder: _buildGroupSwitcher,
                    emptyBuilder: _buildEmpty,
                    heroType: HeroType.never,
                    onTileTap: (item, navigate) => _onCandidateTap(item),
                    selectableItem: (item) => false,
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

  /// The group switcher pinned above the sections.
  ///
  /// It selects which group's range is shown; it never changes the wallpapaper's
  /// current group, which is a group action and belongs to the group list.
  Widget _buildGroupSwitcher(BuildContext context) {
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
              child: ChoiceChip(
                avatar: group.current ? Icon(AIcons.visibleRangeActive, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
                label: Text('${group.number}  ${wallpaperGroupName(context, group)}'),
                selected: selected == group.id,
                labelStyle: group.enabled ? null : TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                onSelected: (_) => unawaited(_controller.selectGroup(group.id)),
              ),
            ),
        ],
      ),
    );
  }

  Map<ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>> _buildSections(BuildContext context) {
    final range = _controller.range;
    if (range == null) return const {};
    final supplementsOutside = range.order.isIntersectFirst;
    final result = <ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>>{};
    for (final section in buildVisibleRangeSections(range: range, presets: _controller.presets)) {
      final countText = switch (section.kind) {
        VisibleRangeCandidateKind.base => '${section.candidates.length}',
        VisibleRangeCandidateKind.restriction || VisibleRangeCandidateKind.supplement => '${section.candidates.where((candidate) => candidate.active).length}/${section.candidates.length}',
      };
      final key = VisibleRangeSectionKey(context, section.kind, countText: countText, supplementsOutside: supplementsOutside);
      final ordered = section.kind == VisibleRangeCandidateKind.base
          ? [...section.candidates.where((candidate) => candidate.isUnrestricted), ...section.candidates.where((candidate) => !candidate.isUnrestricted)]
          : section.candidates;
      result[key] = [
        for (final candidate in ordered) FilterGridItem(VisibleRangeCandidateFilter(candidate), null),
      ];
    }
    if (_controller.activeStyle == VisibleRangeActiveStyle.section) {
      final active = buildVisibleRangeActiveCandidates(range: range, presets: _controller.presets);
      result[VisibleRangeActiveSectionKey(context, restricted: range.isRestricted)] = [
        for (final candidate in active) FilterGridItem(VisibleRangeCandidateFilter(candidate, summary: true), null),
      ];
    }
    return result;
  }

  Widget _buildTile(BuildContext context, FilterGridItem<VisibleRangeCandidateFilter> item, Size tileSize) {
    final candidate = item.filter.candidate;
    final summary = item.filter.summary;
    return MetaData(
      metaData: ScalerMetadata(item),
      child: VisibleRangeTile(
        gridItem: item,
        stats: candidate.isGallery ? _resultStats : _stats[candidate.statsKey],
        tileLayout: settings.getTileLayout(GroupedWallpaperPage.routeName),
        tileSize: tileSize,
        summary: summary,
        showStateIcon: !candidate.isGallery,
        onTap: () => _onCandidateTap(item),
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

  void _onCandidateTap(FilterGridItem<VisibleRangeCandidateFilter> item) {
    final candidate = item.filter.candidate;
    if (_controller.selectedGroupId == null) return;
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    if (item.filter.summary) {
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

  List<PopupMenuEntry<_PageAction>> _menuEntries(BuildContext context) {
    final l10n = context.l10n;
    final range = _controller.range;
    final locked = range?.locked ?? false;
    return [
      PopupMenuItem<_PageAction>(
        value: _PageAction.order,
        child: _menuRow(context, AIcons.sortOrder, l10n.visibleRangeOrder),
      ),
      PopupMenuItem<_PageAction>(
        value: _PageAction.lock,
        child: _menuRow(context, locked ? AIcons.locked : AIcons.unlocked, locked ? l10n.visibleRangeUnlock : l10n.visibleRangeLock),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<_PageAction>(
        value: _PageAction.about,
        child: _menuRow(context, AIcons.info, l10n.visibleRangeAbout),
      ),
    ];
  }

  Widget _menuRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ],
    );
  }

  Future<void> _onMenuSelected(_PageAction action) async {
    if (_controller.selectedGroupId == null) {
      _showBlocked();
      return;
    }
    switch (action) {
      case _PageAction.order:
        await _pickOrder();
      case _PageAction.lock:
        await _toggleLock();
      case _PageAction.about:
        await _openAbout();
    }
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
