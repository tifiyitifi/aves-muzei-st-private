import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_open.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_apply.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_action_delegate.dart';
import 'package:aves/features/visible_range/view/visible_range_active_footer.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_group_actions.dart';
import 'package:aves/features/visible_range/view/visible_range_group_open.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/features/visible_range/view/visible_range_page_sections.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_lock_dialog.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_rule_actions.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
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
  editGroup,
  editCurrentGroup,
  renameGroup,
  deleteGroup,
  moveGroupLeft,
  moveGroupRight,
  applyToMediaSet,
  reAddDefaults,
  wallpaperGroups,
  lockDetailed,
  about,
}

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
    final filter = _controller.galleryFilter;
    final filters = filter == null ? const <CollectionFilter>{} : <CollectionFilter>{filter};
    final stats = await VisibleRangeCandidateStatsLoader.load([filters]);
    if (!mounted || token != _resultToken) return;
    setState(() => _resultStats = stats.values.firstOrNull);
  }

  Future<void> _refreshStats() async {
    final filtersByKey = <String, Set<CollectionFilter>>{};
    for (final section in buildVisibleRangePageSections(
      groups: _controller.galleryGroups,
      currentGroupId: _controller.currentGalleryGroupId,
      outside: _controller.outside,
    )) {
      for (final candidate in section.candidates) {
        if (candidate.isGroupAdd) continue;
        filtersByKey.putIfAbsent(candidate.statsKey, () => candidate.filters);
      }
    }
    for (final candidate in buildVisibleRangeActiveCandidates(range: _controller.gallery, outside: _controller.outside)) {
      filtersByKey.putIfAbsent(candidate.statsKey, () => candidate.filters);
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

  /// Whether this page may write the range.
  ///
  /// The range's own lock is the only gate: an unlocked range (or a locked one
  /// with the edit permission) can be edited. There is no second, session-wide
  /// freeze — a lock is unlocked by proving its PIN, and that is all.
  bool get _canEdit => _controller.canEdit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final source = context.read<CollectionSource>();
        final sections = _buildSections(context);
        // The current-visible section repeats conditions from the sections above,
        // so it must not feed the rule actions or the multi-selection twice.
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
        final page = FilterGroupProvider(
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
                    selectableItem: (item) => !item.filter.summary && (item.filter.candidate.isApplicable || item.filter.candidate.isGroup),
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
        return page;
      },
    );
  }

  Map<ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>> _buildSections(BuildContext context) {
    final outside = _controller.outside;
    final result = <ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>>{};
    final pageSections = buildVisibleRangePageSections(
      groups: _controller.galleryGroups,
      currentGroupId: _controller.currentGalleryGroupId,
      outside: outside,
    );
    for (final section in pageSections) {
      switch (section.kind) {
        case VisibleRangePageSectionKind.groups:
          final count = section.candidates.where((candidate) => candidate.isGroup).length;
          result[VisibleRangeGroupSectionKey(context, countText: '$count')] = [
            for (final candidate in section.candidates) FilterGridItem(VisibleRangeCandidateFilter(candidate), null),
          ];
        case VisibleRangePageSectionKind.outsideRestriction:
        case VisibleRangePageSectionKind.outsideSupplement:
          final kind = section.kind == VisibleRangePageSectionKind.outsideRestriction ? VisibleRangeCandidateKind.restriction : VisibleRangeCandidateKind.supplement;
          final candidates = section.candidates.isEmpty ? [_outsideEmptyCandidate(kind)] : section.candidates;
          final countText = visibleRangeSectionCountText(kind, section.candidates);
          result[VisibleRangeSectionKey(context, kind, countText: countText, outside: true)] = [
            for (final candidate in candidates) FilterGridItem(VisibleRangeCandidateFilter(candidate), null),
          ];
      }
    }
    if (_controller.activeStyle == VisibleRangeActiveStyle.section) {
      // The same conditions, repeated as a read-only group at the bottom: it
      // shares the grid's columns, tile size and pinch zoom with the groups
      // above, so it is a section rather than a separate footer strip.
      final active = buildVisibleRangeActiveCandidates(range: _controller.gallery, outside: outside);
      result[VisibleRangeActiveSectionKey(context, restricted: _controller.galleryRestricted)] = [
        for (final candidate in active) FilterGridItem(VisibleRangeCandidateFilter(candidate, summary: true), null),
      ];
    }
    return result;
  }

  /// The slot an empty outside section shows, so its header never disappears.
  VisibleRangeCandidate _outsideEmptyCandidate(VisibleRangeCandidateKind kind) => VisibleRangeCandidate(
    id: 'outside.empty.${kind.name}',
    kind: kind,
    filters: const {},
    labelKey: 'visibleRangeSectionEmpty',
    placeholder: true,
  );

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
          selectable: !summary && (candidate.isApplicable || candidate.isGroup),
          selecting: _selection.isSelecting,
          selected: _selection.selectedItems.contains(item),
          onTap: () => _onCandidateTap(item),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final range = _controller.gallery;
    final baseCandidates = buildVisibleRangeSections(range: range).first.candidates;
    final activeBase = baseCandidates.firstWhereOrNull((candidate) => candidate.active && !candidate.isUnrestricted);
    final activeRules = [
      for (final kind in range.order.isIntersectFirst
          ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement]
          : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
        for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
      for (final kind in [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement])
        for (final rule in _controller.outside.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
    ];
    return VisibleRangeActiveFooter(
      range: range,
      outside: _controller.outside,
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
      final selectedGroupId = _editGroupId(selection);
      final actions = <Widget>[
        if (selectedGroupId != null)
          IconButton(
            icon: const Icon(AIcons.edit),
            tooltip: l10n.visibleRangeGroupEdit,
            onPressed: () => unawaited(_editGroup(selectedGroupId)),
          ),
        if (selectedRule != null)
          IconButton(
            icon: const Icon(AIcons.edit),
            tooltip: l10n.visibleRangeEditRule,
            onPressed: () => unawaited(_showRuleEditor(selectedRule)),
          ),
        if (selection.selectedItemCount > 0 && selectedGroupId == null)
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
      final editGroupId = _editGroupId(selection);
      if (editGroupId != null) {
        final isZero = _controller.isGroupZero(editGroupId);
        return [
          if (!isZero) ...[
            _menuItem<_MoreAction>(context, _MoreAction.editGroup, AIcons.edit, context.l10n.visibleRangeGroupEdit),
            _menuItem<_MoreAction>(context, _MoreAction.renameGroup, AIcons.edit, context.l10n.visibleRangeGroupRename),
            _menuItem<_MoreAction>(context, _MoreAction.moveGroupLeft, Icons.chevron_left, context.l10n.visibleRangeGroupMoveLeft),
            _menuItem<_MoreAction>(context, _MoreAction.moveGroupRight, Icons.chevron_right, context.l10n.visibleRangeGroupMoveRight),
            _menuItem<_MoreAction>(context, _MoreAction.deleteGroup, AIcons.delete, context.l10n.visibleRangeGroupDelete),
          ],
        ];
      }
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
      // The same action the selected-group menu offers, reachable without a long
      // press: it edits whichever group browsing is on. Group 0 is
      // 「Unrestricted」 and holds no conditions, so the entry is disabled there.
      PopupMenuItem<_MoreAction>(
        value: _MoreAction.editCurrentGroup,
        enabled: !_controller.isGroupZero(_controller.currentGalleryGroupId),
        child: _menuRow(context, AIcons.edit, l10n.visibleRangeGroupEditCurrent),
      ),
      const PopupMenuDivider(),
      _menuItem(context, _MoreAction.reAddDefaults, AIcons.newTier, l10n.visibleRangeReAddDefaults),
      const PopupMenuDivider(),
      // The wallpaper groups own their own condition pool, so they are reached
      // from here: the page is a navigation destination of its own, and this
      // entry navigates to it the way a bar destination does (it replaces the
      // stack) rather than pushing a sub-page over the range page.
      _menuItem(context, _MoreAction.wallpaperGroups, AIcons.wallpaper, l10n.wallpaperGroupOpen),
      const PopupMenuDivider(),
      _menuItem(context, _MoreAction.lockDetailed, AIcons.locked, l10n.visibleRangeLockSheetTitle),
      _menuItem(context, _MoreAction.about, AIcons.info, l10n.visibleRangeAbout),
    ];
  }

  PopupMenuItem<T> _menuItem<T>(BuildContext context, T value, IconData icon, String text) {
    return PopupMenuItem<T>(value: value, child: _menuRow(context, icon, text));
  }

  /// The group the overflow's edit action targets, when there is one.
  ///
  /// With no selection it is the current group; a single selected group tile
  /// edits itself. A condition or a multi-group selection has no single target.
  String? _editGroupId(Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection) => visibleRangeEditGroupId(
        selecting: selection.isSelecting,
        selectedItemCount: selection.selectedItemCount,
        selectedGroupIds: [
          for (final item in selection.selectedItems)
            if (item.filter.candidate.isGroup) item.filter.candidate.groupId,
        ],
        currentGroupId: _controller.currentGalleryGroupId,
      );

  /// Opens the current group's editor.
  ///
  /// Group 0 is the 「Unrestricted」 sentinel and holds no conditions, so there is
  /// nothing to edit.
  Future<void> _editGroup(String id) async {
    if (!mounted) return;
    if (_controller.isGroupZero(id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeGroupZeroReadOnly)));
      return;
    }
    if (!_controller.canEditGroup(id)) {
      _showBlocked();
      return;
    }
    _browseSelection();
    await openVisibleRangeGroupEditor(context, groupId: id);
  }

  Future<void> _renameGroup(String id) async {
    if (_controller.isGroupZero(id) || !_controller.canEditGroup(id)) {
      _showBlocked();
      return;
    }
    final group = _controller.galleryGroupById(id);
    if (group == null || !mounted) return;
    final l10n = context.l10n;
    final controller = TextEditingController(text: group.name.startsWith('@') ? '' : group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.visibleRangeGroupRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.visibleRangeGroupName, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _controller.renameGalleryGroup(id, name: name);
    _browseSelection();
  }

  Future<void> _deleteGroup(String id) async {
    if (_controller.isGroupZero(id) || !_controller.canEditGroup(id)) {
      _showBlocked();
      return;
    }
    final group = _controller.galleryGroupById(id);
    if (group == null || !mounted) return;
    final name = group.name.startsWith('@') ? visibleRangePresetLabel(context, group.name.substring(1)) : group.name;
    final displayName = name.isEmpty ? context.l10n.wallpaperGroupFallbackName(_controller.galleryGroupNumber(id)) : name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.visibleRangeGroupDeleteConfirm(displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.deleteGalleryGroups({id});
    _browseSelection();
  }

  Future<void> _moveGroup(String id, int delta) async {
    if (!_controller.canEditGroup(id)) {
      _showBlocked();
      return;
    }
    await _controller.moveGalleryGroup(id, delta);
    _browseSelection();
  }

  Future<void> _createGroup() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.visibleRangeGroupNew),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.visibleRangeGroupName, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null) return;
    await _controller.addGalleryGroup(name: name);
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
      // The current-visible section repeats conditions from the sections above:
      // tapping one toggles it, and the gallery preview is inert.
      final rule = candidate.rule;
      if (rule != null) _toggleRule(rule);
      return;
    }
    if (_selection.isSelecting) {
      if (candidate.isApplicable || candidate.isGroup) _selection.toggleSelection(item);
      return;
    }
    if (candidate.isGroupAdd) {
      unawaited(_createGroup());
      return;
    }
    if (candidate.isGroup) {
      _selectGroup(candidate.groupId);
      return;
    }
    final rule = candidate.rule;
    if (rule != null) _toggleRule(rule);
  }

  /// Switches browsing to [id].
  ///
  /// A gallery group change invalidates the wallpaper page's "ignore the gallery
  /// range" choice: that choice was made about the group that was current then,
  /// and silently keeping it would hide the newly chosen group's restriction.
  void _selectGroup(String id) {
    if (!_canEdit) {
      _showBlocked();
      return;
    }
    unawaited(() async {
      await _controller.selectGalleryGroup(id);
      VisibleRangeGate.setGallerySuspended(false);
    }());
  }

  void _toggleRule(VisibleRangeRule rule) {
    if (!_canEdit) {
      _showBlocked();
      return;
    }
    unawaited(_controller.toggleRule(rule.id));
  }

  void _cancelBase() {
    if (!_canEdit) {
      _showBlocked();
      return;
    }
    unawaited(_controller.clearSources(_controller.gallery.id));
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
      // Unlocking protects the user's chosen restriction: prove the PIN first.
      if (!await ensureVisibleRangeUnlocked(context)) return;
      if (!mounted) return;
      await _controller.unlock();
      return;
    }
    // Locking only adds protection, so it needs no PIN.
    await _controller.lockWithPreset(_controller.lastLockPreset);
  }

  void _showBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeManagementBlocked)));
  }

  /// Single-rule actions. Locked rules show only read-only actions.
  Future<void> _showRuleEditor(VisibleRangeRule rule) async {
    final action = await showVisibleRangeRuleActions(context, rule: rule, canEdit: _canEdit, allowMoveToBase: false);
    if (!mounted || action == null) return;
    switch (action) {
      case VisibleRangeRuleAction.rename:
        await _renameRule(rule);
      case VisibleRangeRuleAction.moveToRestriction:
        await _moveRule(rule, VisibleRangeRuleKind.restriction);
      case VisibleRangeRuleAction.moveToSupplement:
        await _moveRule(rule, VisibleRangeRuleKind.supplement);
      case VisibleRangeRuleAction.moveToBase:
        await _moveRuleToBase(rule);
      case VisibleRangeRuleAction.activateReplace:
        await _activate(rule, VisibleRangeActivationMode.override);
      case VisibleRangeRuleAction.activateAppend:
        await _activate(rule, VisibleRangeActivationMode.append);
      case VisibleRangeRuleAction.delete:
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
    await _controller.moveRuleToKind(rule.rangeId, rule.id, kind);
    _browseSelection();
  }

  Future<void> _moveRuleToBase(VisibleRangeRule rule) async {
    await _controller.moveRuleToKind(rule.rangeId, rule.id, VisibleRangeRuleKind.source);
    _browseSelection();
  }

  Future<void> _activate(VisibleRangeRule rule, VisibleRangeActivationMode mode) async {
    _browseSelection();
    await applyVisibleRangeCandidates(
      context,
      rangeId: rule.rangeId,
      candidates: [VisibleRangeCandidate.fromRule(rule)],
      replace: mode == VisibleRangeActivationMode.override,
    );
  }

  /// Takes the selected candidates out to the media set.
  ///
  /// The union of their filters is appended to what the media set currently
  /// shows, and every target is remembered for the pin sheet's write-back list.
  Future<void> _applySelectionToMediaSet() async {
    if (!_selection.isSelecting) return;
    final items = _selection.selectedItems;
    final candidates = [
      for (final item in items)
        if (!item.filter.summary && item.filter.candidate.isApplicable) item.filter.candidate,
    ];
    if (candidates.isEmpty) return;
    final rangeId = items.map((item) => item.filter.candidate.rule?.rangeId).nonNulls.firstOrNull ?? _controller.gallery.id;
    _browseSelection();
    await applyVisibleRangeCandidates(context, rangeId: rangeId, candidates: candidates);
  }

  Future<void> _deleteRules(Set<VisibleRangeRule> rules) async {
    if (!_canEdit) {
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

  Future<void> _onExtraMenuSelected(Object value) async {
    if (value is! _MoreAction) return;
    switch (value) {
      case _MoreAction.editRule:
        final rule = _selectedRule(_selection);
        if (rule != null) await _showRuleEditor(rule);
      case _MoreAction.editGroup:
        final id = _editGroupId(_selection);
        if (id != null) await _editGroup(id);
      case _MoreAction.editCurrentGroup:
        await _editGroup(_controller.currentGalleryGroupId);
      case _MoreAction.renameGroup:
        final id = _editGroupId(_selection);
        if (id != null) await _renameGroup(id);
      case _MoreAction.deleteGroup:
        final id = _editGroupId(_selection);
        if (id != null) await _deleteGroup(id);
      case _MoreAction.moveGroupLeft:
        final id = _editGroupId(_selection);
        if (id != null) await _moveGroup(id, -1);
      case _MoreAction.moveGroupRight:
        final id = _editGroupId(_selection);
        if (id != null) await _moveGroup(id, 1);
      case _MoreAction.applyToMediaSet:
        await _applySelectionToMediaSet();
      case _MoreAction.reAddDefaults:
        if (!_canEdit) {
          _showBlocked();
          return;
        }
        final result = await _controller.reAddDefaultPresets();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeReAddDefaultsResult(result.added, result.skipped))));
      case _MoreAction.wallpaperGroups:
        await _openWallpaperGroups();
      case _MoreAction.lockDetailed:
        await _lockDetailed();
      case _MoreAction.about:
        await _openAbout();
    }
  }

  /// Opens the wallpaper groups.
  ///
  /// The drawer's wallpaper-groups entry opens through the same helper, so the
  /// shared mode (one entry hosts both pages) behaves the same whichever entry
  /// point the user takes. In the shared mode the page is already on screen, so
  /// the call only flips the entry; with a separate entry it replaces the stack
  /// like a bar destination, and the page's close action lands on the range page.
  Future<void> _openWallpaperGroups() async {
    if (!mounted) return;
    await openGroupedWallpaperGroups(context);
  }

  Future<void> _lockDetailed() async {
    // Changing a locked range's permissions is as much an edit as unlocking it.
    if (_controller.gallery.locked && !await ensureVisibleRangeUnlocked(context)) return;
    if (!mounted) return;
    final permissions = await showDialog<VisibleRangePermissions>(
      context: context,
      builder: (context) => VisibleRangeLockDialog(initialPreset: _controller.lastLockPreset),
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

