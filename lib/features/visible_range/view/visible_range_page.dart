import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_apply.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_action_delegate.dart';
import 'package:aves/features/visible_range/view/visible_range_active_footer.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/scaling.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/tile_extent_controller.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The visible-range page, built on the album page's chip grid.
///
/// Section headers, layout, scaling, selection, the app bar, drawer and bottom
/// navigation all come from `FilterGridPage`/`FilterGridAppBar`. The feature
/// supplies only the candidate tiles and the "current range" footer.
class VisibleRangePage extends StatefulWidget {
  static const routeName = '/visible_range';

  const new({super.key});

  @override
  State<VisibleRangePage> createState() => _VisibleRangePageState();
}

enum _MoreAction {
  editRule,
  applyToMediaSet,
  order,
  reAddDefaults,
  wallpaperGroups,
  lockDetailed,
  about,
}

enum _RuleAction { rename, moveToRestriction, moveToSupplement, moveToBase, activateReplace, activateAppend, delete }

enum _PresetAction { edit, delete }

class _VisibleRangePageState extends State<VisibleRangePage> {
  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  VisibleRangeCandidateStats? _resultStats;
  int _resultToken = 0;

  /// The page's multi-selection.
  ///
  /// The page owns it instead of looking it up in the widget tree: the handlers
  /// below run from the `State`'s context, which sits above the provider created
  /// in `build`, so an ancestor lookup would never find it. Holding the instance
  /// also states who is responsible for disposing it.
  ///
  /// `toSelectableItems` is passed explicitly because the model requires the
  /// choice: a grid item is selected as itself.
  final _selection = Selection<FilterGridItem<VisibleRangeCandidateFilter>>(toSelectableItems: null);

  VisibleRangeController get _controller => visibleRangeController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.init());
    unawaited(_refreshResultStats());
    unawaited(_refreshStats());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _selection.dispose();
    _appBarHeightNotifier.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshResultStats());
    unawaited(_refreshStats());
  }

  /// Count and cover of what the current range resolves to.
  ///
  /// This is the only stat that needs a cover for the whole range: the footer's
  /// gallery chip previews the result, while the candidate tiles use their own
  /// per-filter stats.
  Future<void> _refreshResultStats() async {
    final token = ++_resultToken;
    final filter = _controller.gallery.resolve();
    final filters = filter == null ? const <CollectionFilter>{} : <CollectionFilter>{filter};
    final stats = await VisibleRangeCandidateStatsLoader.load([filters]);
    if (!mounted || token != _resultToken) return;
    setState(() => _resultStats = stats.values.firstOrNull);
  }

  Future<void> _refreshStats() async {
    final filtersByKey = <String, Set<CollectionFilter>>{};
    for (final section in buildVisibleRangeSections(range: _controller.gallery, presets: _controller.presets)) {
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
        // The active section repeats conditions from the groups above, so it
        // must not feed the rule actions or the multi-selection twice.
        final items = sections.values.expand((list) => list).where((item) => !item.filter.summary && item.filter.candidate.rule != null).toList();
        final delegate = VisibleRangeActionDelegate(
          controller: _controller,
          settingsRouteKey: VisibleRangePage.routeName,
          itemBuilder: () => items,
          onRename: (context, rule) => _renameRule(rule),
          onDelete: (context, rules) => _deleteRules(rules),
          onActivate: (context, rule) => _activate(rule, VisibleRangeActivationMode.override),
          extraLayoutRows: (context) => [_buildActiveStyleRow(context)],
        );
        return FilterGroupProvider(
          // The visible-range candidates are not the album page's group
          // children: shadow the app-wide notifier so a stale album group
          // cannot show a crumb or swallow the back gesture here.
          child: ChangeNotifierProvider<Selection<FilterGridItem<VisibleRangeCandidateFilter>>>.value(
            value: _selection,
            child: Builder(
              builder: (context) {
                final scrollController = PrimaryScrollController.of(context);
                return QueryProvider(
                  startEnabled: settings.getShowTitleQuery(VisibleRangePage.routeName),
                  child: FilterGridPage<VisibleRangeCandidateFilter>(
                    settingsRouteKey: VisibleRangePage.routeName,
                    appBar: FilterGridAppBar<VisibleRangeCandidateFilter, VisibleRangeActionDelegate>(
                      source: source,
                      title: context.l10n.visibleRangePageTitle,
                      titleStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0,
                        fontFeatures: const [],
                      ),
                      actionDelegate: delegate,
                      extraActionsBuilder: _buildExtraActions,
                      extraMenuEntriesBuilder: _buildExtraMenuEntries,
                      onExtraMenuSelected: (value) => unawaited(_onExtraMenuSelected(value)),
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
                    emptyBuilder: () => Center(child: Text(context.l10n.visibleRangeNoCandidates)),
                    heroType: HeroType.never,
                    onTileTap: (item, navigate) => _onCandidateTap(item),
                    selectableItem: (item) => !item.filter.summary && item.filter.candidate.isApplicable,
                    tileBuilder: _buildTile,
                    // The section form repeats the active conditions as the last
                    // grid section instead of a separate footer.
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

  Map<ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>> _buildSections(BuildContext context) {
    final range = _controller.gallery;
    final supplementsOutside = range.order.isIntersectFirst;
    final result = <ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>>{};
    for (final section in buildVisibleRangeSections(range: range, presets: _controller.presets)) {
      // Each header counts the conditions its own group contributes, not the
      // entries left visible: the base group advertises how many choices it
      // shows, and the rule groups show active/total. The resulting item total
      // lives on the footer's gallery chip.
      final countText = switch (section.kind) {
        VisibleRangeCandidateKind.base => '${section.candidates.length}',
        VisibleRangeCandidateKind.restriction || VisibleRangeCandidateKind.supplement => '${section.candidates.where((candidate) => candidate.active).length}/${section.candidates.length}',
      };
      final key = VisibleRangeSectionKey(context, section.kind, countText: countText, supplementsOutside: supplementsOutside);
      // The bundled order is the page's order: the groups read the same on every
      // install instead of reshuffling when a cover date changes.
      final ordered = section.kind == VisibleRangeCandidateKind.base
          ? [...section.candidates.where((candidate) => candidate.isUnrestricted), ...section.candidates.where((candidate) => !candidate.isUnrestricted)]
          : section.candidates;
      result[key] = [
        for (final candidate in ordered)
          // Cover and count stay in the stats map: a candidate is a filter set,
          // not a covered filter, so the grid item carries no entry of its own.
          FilterGridItem(VisibleRangeCandidateFilter(candidate), null),
      ];
    }
    if (_controller.activeStyle == VisibleRangeActiveStyle.section) {
      // The same conditions, repeated as a read-only group at the bottom: it
      // shares the grid's columns, tile size and pinch zoom with the groups
      // above, so it is a section rather than a separate footer strip.
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
      child: ListenableBuilder(
        listenable: _selection,
        builder: (context, _) => VisibleRangeTile(
          gridItem: item,
          // The gallery preview stands for the whole range, not for the empty
          // filter set it shares its stats key with.
          stats: candidate.isGallery ? _resultStats : _stats[candidate.statsKey],
          tileLayout: settings.getTileLayout(VisibleRangePage.routeName),
          tileSize: tileSize,
          summary: summary,
          showStateIcon: !candidate.isGallery,
          selectable: !summary && candidate.isApplicable,
          selecting: _selection.isSelecting,
          selected: _selection.selectedItems.contains(item),
          onTap: () => _onCandidateTap(item),
          onLongPress: !summary && candidate.preset != null && !candidate.preset!.builtin ? () => _showPresetEditor(candidate.preset!) : null,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final range = _controller.gallery;
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
      // The footer tiles match the grid cells above instead of shrinking to a
      // fixed size.
      tileExtent: context.select<TileExtentController, double>((controller) => controller.extentNotifier.value),
      onCancelBase: _cancelBase,
      onCancelRule: (candidate) {
        final rule = candidate.rule;
        if (rule != null) _toggleRule(rule);
      },
      onAbout: _openAbout,
    );
  }

  List<Widget> _buildExtraActions(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection,
    VisibleRangeActionDelegate delegate,
  ) {
    final l10n = context.l10n;
    final range = _controller.gallery;
    final lockButton = IconButton(
      icon: Icon(range.locked ? AIcons.locked : AIcons.unlocked),
      tooltip: range.locked ? l10n.visibleRangeUnlock : l10n.visibleRangeLock,
      onPressed: _toggleLock,
    );
    if (selection.isSelecting) {
      // On a TV rail there is no overflow menu, so the selection actions have to
      // stay reachable as icons.
      final selectedRule = _selectedRule(selection);
      final actions = <Widget>[
        if (selectedRule != null)
          IconButton(
            icon: const Icon(AIcons.edit),
            tooltip: l10n.visibleRangeEditRule,
            onPressed: () => unawaited(_showRuleEditor(selectedRule)),
          ),
        if (selection.selectedItemCount > 0)
          IconButton(
            icon: const Icon(AIcons.apply),
            tooltip: l10n.visibleRangeApplyToMediaSet,
            onPressed: () => unawaited(_applySelectionToMediaSet()),
          ),
      ];
      return settings.useTvLayout ? actions : const [];
    }
    if (!settings.useTvLayout) return [lockButton];
    return [
      lockButton,
      // The app bar's ⋮ is the single overflow on phones. The TV rail has none,
      // so the feature keeps its own menu there instead of losing the actions.
      PopupMenuButton<_MoreAction>(
        icon: const Icon(AIcons.more),
        tooltip: l10n.visibleRangeMore,
        onSelected: (action) => unawaited(_onExtraMenuSelected(action)),
        itemBuilder: _menuEntries,
      ),
    ];
  }

  /// Feature entries injected into the app bar's single overflow menu.
  List<PopupMenuEntry<Object>> _buildExtraMenuEntries(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection,
    VisibleRangeActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      final selectedRule = _selectedRule(selection);
      return [
        if (selectedRule != null) _menuItem<_MoreAction>(context, _MoreAction.editRule, AIcons.edit, context.l10n.visibleRangeEditRule),
        if (selection.selectedItemCount > 0) _menuItem<_MoreAction>(context, _MoreAction.applyToMediaSet, AIcons.apply, context.l10n.visibleRangeApplyToMediaSet),
      ];
    }
    return _menuEntries(context);
  }

  List<PopupMenuEntry<_MoreAction>> _menuEntries(BuildContext context) {
    final l10n = context.l10n;
    return [
      _menuItem(context, _MoreAction.order, AIcons.sortOrder, l10n.visibleRangeOrder),
      _menuItem(context, _MoreAction.reAddDefaults, AIcons.newTier, l10n.visibleRangeReAddDefaults),
      const PopupMenuDivider(),
      // The wallpaper groups own their own ranges, so they are reachable from
      // the range page instead of the bottom bar: one filter entry, one place.
      _menuItem(context, _MoreAction.wallpaperGroups, AIcons.wallpaper, l10n.wallpaperGroupsTitle),
      const PopupMenuDivider(),
      _menuItem(context, _MoreAction.lockDetailed, AIcons.locked, l10n.visibleRangeLockSheetTitle),
      _menuItem(context, _MoreAction.about, AIcons.info, l10n.visibleRangeAbout),
    ];
  }

  PopupMenuItem<T> _menuItem<T>(BuildContext context, T value, IconData icon, String text) {
    return PopupMenuItem<T>(value: value, child: _menuRow(context, icon, text));
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

  VisibleRangeRule? _selectedRule(Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection) {
    if (!selection.isSelecting) return null;
    final items = selection.selectedItems;
    if (items.length != 1) return null;
    return items.first.filter.candidate.rule;
  }

  void _onCandidateTap(FilterGridItem<VisibleRangeCandidateFilter> item) {
    final candidate = item.filter.candidate;
    if (item.filter.summary) {
      // The active section repeats conditions from the groups above: tapping one
      // cancels it, and the gallery preview is inert.
      final rule = candidate.rule;
      if (rule != null) {
        _toggleRule(rule);
      } else if (!candidate.isGallery && !candidate.isUnrestricted) {
        _cancelBase();
      }
      return;
    }
    if (_selection.isSelecting) {
      if (candidate.isApplicable) _selection.toggleSelection(item);
      return;
    }
    switch (candidate.kind) {
      case VisibleRangeCandidateKind.base:
        if (candidate.isUnrestricted) {
          unawaited(_selectBase(null));
        } else if (candidate.preset != null) {
          unawaited(_selectBase(candidate.preset!));
        }
      case VisibleRangeCandidateKind.restriction:
      case VisibleRangeCandidateKind.supplement:
        final rule = candidate.rule;
        if (rule != null) _toggleRule(rule);
    }
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

  Widget _menuRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ],
    );
  }

  // actions

  Future<void> _toggleLock() async {
    final range = _controller.gallery;
    if (range.locked) {
      await _controller.unlock();
      return;
    }
    await _controller.lockWithPreset(_controller.lastLockPreset);
  }

  void _showBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeManagementBlocked)));
  }

  Future<void> _selectBase(VisibleRangePreset? preset) async {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    if (preset == null) {
      await _controller.clearBase();
    } else {
      await _controller.selectBase(presetId: preset.id, name: preset.name, filters: preset.filters);
    }
  }

  Future<void> _deletePreset(VisibleRangePreset preset) async {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    await _controller.deleteBasePreset(preset.id);
  }

  /// A user base preset is editable and removable, unlike the built-in ones.
  Future<void> _showPresetEditor(VisibleRangePreset preset) async {
    final l10n = context.l10n;
    final action = await showModalBottomSheet<_PresetAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(visibleRangePresetLabel(context, preset.name)),
              subtitle: preset.description.isEmpty ? null : Text(preset.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(AIcons.edit),
              title: Text(l10n.visibleRangeActionRename),
              onTap: () => Navigator.pop(context, _PresetAction.edit),
            ),
            ListTile(
              leading: const Icon(AIcons.delete),
              title: Text(l10n.visibleRangeActionDelete),
              onTap: () => Navigator.pop(context, _PresetAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PresetAction.edit:
        await _editPresetNameDescription(preset);
      case _PresetAction.delete:
        await _deletePreset(preset);
    }
  }

  Future<void> _editPresetNameDescription(VisibleRangePreset preset) async {
    final result = await _showNameDescriptionDialog(
      title: context.l10n.visibleRangeEditNameDescription,
      initialName: preset.name,
      initialDescription: preset.description,
    );
    if (result == null) return;
    await _controller.updateBasePreset(
      preset.id,
      name: result.name.isEmpty ? preset.name : result.name,
      description: result.description,
    );
    _browseSelection();
  }

  /// Single-rule actions. Locked rules show only read-only actions.
  Future<void> _showRuleEditor(VisibleRangeRule rule) async {
    final l10n = context.l10n;
    final editable = _controller.canEdit;
    final title = visibleRangeRuleLabel(context, rule);
    final action = await showModalBottomSheet<_RuleAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title.isEmpty ? _kindLabel(context, rule.kind) : title),
              subtitle: Text(
                [rule.description, _kindLabel(context, rule.kind)].where((v) => v.isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(AIcons.rename),
              title: Text(l10n.visibleRangeActionRename),
              enabled: editable,
              onTap: () => Navigator.pop(context, _RuleAction.rename),
            ),
            ListTile(
              leading: const Icon(AIcons.visibleRangeRestriction),
              title: Text(l10n.visibleRangeActionMoveToRestriction),
              enabled: editable && rule.kind != VisibleRangeRuleKind.restriction,
              onTap: () => Navigator.pop(context, _RuleAction.moveToRestriction),
            ),
            ListTile(
              leading: const Icon(AIcons.visibleRangeSupplement),
              title: Text(l10n.visibleRangeActionMoveToSupplement),
              enabled: editable && rule.kind != VisibleRangeRuleKind.supplement,
              onTap: () => Navigator.pop(context, _RuleAction.moveToSupplement),
            ),
            ListTile(
              leading: const Icon(AIcons.folder),
              title: Text(l10n.visibleRangeActionMoveToBase),
              enabled: editable,
              onTap: () => Navigator.pop(context, _RuleAction.moveToBase),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(AIcons.search),
              title: Text(l10n.visibleRangeActionActivateReplace),
              onTap: () => Navigator.pop(context, _RuleAction.activateReplace),
            ),
            ListTile(
              leading: const Icon(AIcons.add),
              title: Text(l10n.visibleRangeActionActivateAppend),
              onTap: () => Navigator.pop(context, _RuleAction.activateAppend),
            ),
            ListTile(
              leading: const Icon(AIcons.delete),
              title: Text(l10n.visibleRangeActionDelete),
              enabled: editable,
              onTap: () => Navigator.pop(context, _RuleAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RuleAction.rename:
        await _renameRule(rule);
      case _RuleAction.moveToRestriction:
        await _moveRule(rule, VisibleRangeRuleKind.restriction);
      case _RuleAction.moveToSupplement:
        await _moveRule(rule, VisibleRangeRuleKind.supplement);
      case _RuleAction.moveToBase:
        await _moveRuleToBase(rule);
      case _RuleAction.activateReplace:
        await _activate(rule, VisibleRangeActivationMode.override);
      case _RuleAction.activateAppend:
        await _activate(rule, VisibleRangeActivationMode.append);
      case _RuleAction.delete:
        await _deleteRules({rule});
    }
  }

  Future<void> _renameRule(VisibleRangeRule rule) async {
    final result = await _showNameDescriptionDialog(
      title: context.l10n.visibleRangeEditNameDescription,
      initialName: rule.label.startsWith('@') ? '' : rule.label,
      initialDescription: rule.description,
      nameHint: visibleRangeRuleLabel(context, rule),
    );
    if (result == null) return;
    await _controller.updateRule(rule.copyWith(label: result.name, description: result.description));
    _browseSelection();
  }

  /// Shared editor for the user text of a rule or a base preset.
  Future<({String name, String description})?> _showNameDescriptionDialog({
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
            onPressed: () => Navigator.pop(
              context,
              (name: nameController.text.trim(), description: descriptionController.text.trim()),
            ),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    return result;
  }

  Future<void> _moveRule(VisibleRangeRule rule, VisibleRangeRuleKind kind) async {
    if (rule.kind == kind) return;
    final range = _controller.gallery;
    final position = range.rulesOf(kind).length;
    await _controller.updateRule(rule.copyWith(kind: kind, position: position));
    _browseSelection();
  }

  Future<void> _moveRuleToBase(VisibleRangeRule rule) async {
    final label = visibleRangeRuleLabel(context, rule);
    await _controller.selectBase(presetId: '', name: label, filters: rule.filters);
    await _controller.deleteRules({rule.id});
    _browseSelection();
  }

  Future<void> _activate(VisibleRangeRule rule, VisibleRangeActivationMode mode) async {
    final current = mediaSetTab.currentFilters ?? const <CollectionFilter>{};
    final target = mode == VisibleRangeActivationMode.override ? rule.filters : {...current, ...rule.filters};
    _browseSelection();
    await AvesNavItem(route: CollectionPage.routeName, filters: target).goTo(context, topLevel: false);
  }

  /// Takes the selected candidates out to the media set.
  ///
  /// The union of their filters is appended to what the media set currently
  /// shows, and every target is remembered for the pin sheet's write-back list.
  Future<void> _applySelectionToMediaSet() async {
    if (!_selection.isSelecting) return;
    final candidates = [
      for (final item in _selection.selectedItems)
        if (!item.filter.summary) item.filter.candidate,
    ];
    if (candidates.isEmpty) return;
    _browseSelection();
    await applyVisibleRangeCandidates(context, rangeId: _controller.gallery.id, candidates: candidates);
  }

  Future<void> _deleteRules(Set<VisibleRangeRule> rules) async {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    if (rules.isEmpty) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.visibleRangeDeleteConfirm(rules.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.deleteRules(rules.map((rule) => rule.id).toSet());
    _browseSelection();
  }

  void _browseSelection() {
    if (!mounted) return;
    _selection.browse();
  }

  String _kindLabel(BuildContext context, VisibleRangeRuleKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      VisibleRangeRuleKind.restriction => l10n.visibleRangeRuleKindRestriction,
      VisibleRangeRuleKind.supplement => l10n.visibleRangeRuleKindSupplement,
    };
  }

  Future<void> _onExtraMenuSelected(Object value) async {
    if (value is! _MoreAction) return;
    switch (value) {
      case _MoreAction.editRule:
        final rule = _selectedRule(_selection);
        if (rule != null) await _showRuleEditor(rule);
      case _MoreAction.applyToMediaSet:
        await _applySelectionToMediaSet();
      case _MoreAction.order:
        await _pickOrder();
      case _MoreAction.reAddDefaults:
        if (!_controller.canEdit) {
          _showBlocked();
          return;
        }
        final result = await _controller.reAddDefaultPresets();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeReAddDefaultsResult(result.added, result.skipped))));
      case _MoreAction.wallpaperGroups:
        // The wallpaper page is a peer of this one behind the same bottom-bar
        // entry, not a child page: switching keeps the entry highlighted.
        visibleRangeDestination.value = VisibleRangeDestination.wallpaper;
      case _MoreAction.lockDetailed:
        await _lockDetailed();
      case _MoreAction.about:
        await _openAbout();
    }
  }

  Future<void> _pickOrder() async {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    final l10n = context.l10n;
    final order = await showDialog<VisibleRangeOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.visibleRangeOrder),
        children: [
          _orderTile(
            context,
            title: l10n.visibleRangeOrderIntersectFirst,
            value: VisibleRangeOrder.intersectFirst,
            current: _controller.gallery.order,
          ),
          _orderTile(
            context,
            title: l10n.visibleRangeOrderUnionFirst,
            value: VisibleRangeOrder.unionFirst,
            current: _controller.gallery.order,
          ),
        ],
      ),
    );
    if (order == null) return;
    await _controller.setOrder(order);
  }

  Widget _orderTile(BuildContext context, {required String title, required VisibleRangeOrder value, required VisibleRangeOrder current}) {
    final selected = value == current;
    return ListTile(
      title: Text(title),
      trailing: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      onTap: () => Navigator.pop(context, value),
    );
  }

  Future<void> _lockDetailed() async {
    final permissions = await showDialog<VisibleRangePermissions>(
      context: context,
      builder: (context) => const _LockDialog(),
    );
    if (permissions == null) return;
    await _controller.lock(permissions: permissions);
  }

  Future<void> _openAbout() async {
    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(settings: const RouteSettings(name: VisibleRangeAboutPage.routeName), builder: (_) => const VisibleRangeAboutPage()),
    );
  }
}

class _LockDialog extends StatefulWidget {
  const new();

  @override
  State<_LockDialog> createState() => _LockDialogState();
}

class _LockDialogState extends State<_LockDialog> {
  VisibleRangeLockPreset _preset = visibleRangeController.lastLockPreset;
  late VisibleRangePermissions _permissions = VisibleRangePermissions.of(_preset);

  void _applyPreset(VisibleRangeLockPreset? preset) {
    if (preset == null) return;
    setState(() {
      _preset = preset;
      _permissions = VisibleRangePermissions.of(preset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.visibleRangeLockSheetTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.visibleRangeLockSheetPreset),
            DropdownButton<VisibleRangeLockPreset>(
              value: _preset,
              isExpanded: true,
              onChanged: _applyPreset,
              items: [
                DropdownMenuItem(value: VisibleRangeLockPreset.readOnly, child: Text(l10n.visibleRangeLockSheetReadOnly)),
                DropdownMenuItem(value: VisibleRangeLockPreset.manageable, child: Text(l10n.visibleRangeLockSheetManageable)),
                DropdownMenuItem(value: VisibleRangeLockPreset.full, child: Text(l10n.visibleRangeLockSheetFull)),
              ],
            ),
            const Divider(),
            _permissionTile(l10n.visibleRangePermissionShare, (p) => p.share, (v) => VisibleRangePermissions(
                  share: v,
                  delete: _permissions.delete,
                  edit: _permissions.edit,
                  move: _permissions.move,
                  rename: _permissions.rename,
                  hide: _permissions.hide,
                  vault: _permissions.vault,
                  trash: _permissions.trash,
                  metadata: _permissions.metadata,
                )),
            _permissionTile(l10n.visibleRangePermissionDelete, (p) => p.delete, (v) => _copy(delete: v)),
            _permissionTile(l10n.visibleRangePermissionEdit, (p) => p.edit, (v) => _copy(edit: v)),
            _permissionTile(l10n.visibleRangePermissionMove, (p) => p.move, (v) => _copy(move: v)),
            _permissionTile(l10n.visibleRangePermissionRename, (p) => p.rename, (v) => _copy(rename: v)),
            _permissionTile(l10n.visibleRangePermissionHide, (p) => p.hide, (v) => _copy(hide: v)),
            _permissionTile(l10n.visibleRangePermissionVault, (p) => p.vault, (v) => _copy(vault: v)),
            _permissionTile(l10n.visibleRangePermissionTrash, (p) => p.trash, (v) => _copy(trash: v)),
            _permissionTile(l10n.visibleRangePermissionMetadata, (p) => p.metadata, (v) => _copy(metadata: v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        TextButton(onPressed: () => Navigator.pop(context, _permissions), child: Text(l10n.visibleRangeLockConfirm)),
      ],
    );
  }

  Widget _permissionTile(String title, bool Function(VisibleRangePermissions p) read, VisibleRangePermissions Function(bool value) update) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: read(_permissions),
      onChanged: (value) => setState(() => _permissions = update(value)),
    );
  }

  VisibleRangePermissions _copy({
    bool? share,
    bool? delete,
    bool? edit,
    bool? move,
    bool? rename,
    bool? hide,
    bool? vault,
    bool? trash,
    bool? metadata,
  }) {
    return VisibleRangePermissions(
      share: share ?? _permissions.share,
      delete: delete ?? _permissions.delete,
      edit: edit ?? _permissions.edit,
      move: move ?? _permissions.move,
      rename: rename ?? _permissions.rename,
      hide: hide ?? _permissions.hide,
      vault: vault ?? _permissions.vault,
      trash: trash ?? _permissions.trash,
      metadata: metadata ?? _permissions.metadata,
    );
  }
}
