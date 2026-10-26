import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_counter.dart';
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_action_delegate.dart';
import 'package:aves/features/visible_range/view/visible_range_active_footer.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
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
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:aves_model/aves_model.dart';
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
  addRestriction,
  addSupplement,
  saveBase,
  order,
  save,
  reAddDefaults,
  lockDetailed,
  about,
}

enum _RuleAction { rename, moveToRestriction, moveToSupplement, moveToBase, activateReplace, activateAppend, delete }

class _VisibleRangePageState extends State<VisibleRangePage> {
  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  ({int? base, int? intermediate, int? total})? _counts;
  int _countToken = 0;

  VisibleRangeController get _controller => visibleRangeController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.init());
    unawaited(_refreshCount());
    unawaited(_refreshStats());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _appBarHeightNotifier.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshCount());
    unawaited(_refreshStats());
  }

  Future<void> _refreshCount() async {
    final token = ++_countToken;
    final counts = await VisibleRangeCounter.counts(_controller.gallery);
    if (!mounted || token != _countToken) return;
    setState(() => _counts = counts);
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
        final items = sections.values.expand((list) => list).where((item) => item.filter.candidate.rule != null).toList();
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
          child: SelectionProvider<FilterGridItem<VisibleRangeCandidateFilter>>(
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
                      actionDelegate: delegate,
                      extraActionsBuilder: _buildExtraActions,
                      appBarHeightNotifier: _appBarHeightNotifier,
                      scrollController: scrollController,
                      onGroupCrumbTap: (context, filter) {},
                    ),
                    appBarHeightNotifier: _appBarHeightNotifier,
                    scrollController: scrollController,
                    sections: sections,
                    newFilters: const {},
                    sortFactor: _controller.viewSortFactor,
                    showHeaders: true,
                    selectable: true,
                    emptyBuilder: () => Center(child: Text(context.l10n.visibleRangeNoCandidates)),
                    heroType: HeroType.never,
                    onTileTap: (item, navigate) => _onCandidateTap(context, item),
                    selectableItem: (item) => item.filter.candidate.rule != null,
                    tileBuilder: _buildTile,
                    footerBuilder: _buildFooter,
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
    final counts = _counts;
    final supplementsOutside = range.order.isIntersectFirst;
    final result = <ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>>{};
    for (final section in buildVisibleRangeSections(range: range, presets: _controller.presets)) {
      final stepCount = switch (section.kind) {
        VisibleRangeCandidateKind.base => counts?.base,
        VisibleRangeCandidateKind.restriction => supplementsOutside ? counts?.intermediate : counts?.total,
        VisibleRangeCandidateKind.supplement => supplementsOutside ? counts?.total : counts?.intermediate,
      };
      final key = VisibleRangeSectionKey(context, section.kind, count: stepCount, supplementsOutside: supplementsOutside);
      final sorted = _sortCandidates(context, section.candidates);
      // The fixed Unrestricted base stays first regardless of the sort, like the
      // old page's first base chip.
      final ordered = section.kind == VisibleRangeCandidateKind.base
          ? [...sorted.where((candidate) => candidate.isUnrestricted), ...sorted.where((candidate) => !candidate.isUnrestricted)]
          : sorted;
      result[key] = [
        for (final candidate in ordered)
          FilterGridItem(VisibleRangeCandidateFilter(candidate), _stats[candidate.statsKey]?.cover),
      ];
    }
    return result;
  }

  List<VisibleRangeCandidate> _sortCandidates(BuildContext context, List<VisibleRangeCandidate> candidates) {
    final sorted = [...candidates];
    switch (_controller.viewSortFactor) {
      case SortFactor.chipName:
        sorted.sort((a, b) => visibleRangeCandidateLabel(context, a).toLowerCase().compareTo(visibleRangeCandidateLabel(context, b).toLowerCase()));
      case SortFactor.date:
        sorted.sort((a, b) {
          final aDate = _stats[a.statsKey]?.cover?.bestDate?.millisecondsSinceEpoch ?? 0;
          final bDate = _stats[b.statsKey]?.cover?.bestDate?.millisecondsSinceEpoch ?? 0;
          final byDate = bDate.compareTo(aDate);
          return byDate != 0 ? byDate : visibleRangeCandidateLabel(context, a).compareTo(visibleRangeCandidateLabel(context, b));
        });
      case SortFactor.count:
        sorted.sort((a, b) {
          final byCount = (_stats[b.statsKey]?.count ?? -1).compareTo(_stats[a.statsKey]?.count ?? -1);
          return byCount != 0 ? byCount : visibleRangeCandidateLabel(context, a).compareTo(visibleRangeCandidateLabel(context, b));
        });
      default:
        break;
    }
    return _controller.viewSortReverse ? sorted.reversed.toList() : sorted;
  }

  Widget _buildTile(BuildContext context, FilterGridItem<VisibleRangeCandidateFilter> item, Size tileSize) {
    final candidate = item.filter.candidate;
    return MetaData(
      metaData: ScalerMetadata(item),
      child: VisibleRangeTile(
        gridItem: item,
        stats: _stats[candidate.statsKey],
        tileLayout: settings.getTileLayout(VisibleRangePage.routeName),
        tileSize: tileSize,
        onTap: () => _onCandidateTap(context, item),
        onLongPress: candidate.preset != null && !candidate.preset!.builtin ? () => _deletePreset(candidate.preset!) : null,
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
      statsFor: (candidate) => _stats[candidate.statsKey],
      totalCount: _counts?.total,
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
    if (selection.isSelecting) {
      final selectedRule = _selectedRule(selection);
      return [
        if (selectedRule != null)
          IconButton(
            icon: const Icon(AIcons.edit),
            tooltip: l10n.visibleRangeEditRule,
            onPressed: () => unawaited(_showRuleEditor(selectedRule)),
          ),
      ];
    }
    return [
      IconButton(
        icon: Icon(range.locked ? AIcons.locked : AIcons.unlocked),
        tooltip: range.locked ? l10n.visibleRangeUnlock : l10n.visibleRangeLock,
        onPressed: _toggleLock,
      ),
      PopupMenuButton<_MoreAction>(
        icon: const Icon(AIcons.more),
        tooltip: l10n.visibleRangeMore,
        onSelected: _onMore,
        itemBuilder: (context) => [
          PopupMenuItem(value: _MoreAction.addRestriction, child: _menuRow(context, AIcons.visibleRangeRestriction, l10n.visibleRangeAddRestriction)),
          PopupMenuItem(value: _MoreAction.addSupplement, child: _menuRow(context, AIcons.visibleRangeSupplement, l10n.visibleRangeAddSupplement)),
          PopupMenuItem(value: _MoreAction.saveBase, child: _menuRow(context, AIcons.folder, l10n.visibleRangeSaveBase)),
          const PopupMenuDivider(),
          PopupMenuItem(value: _MoreAction.order, child: _menuRow(context, AIcons.sortOrder, l10n.visibleRangeOrder)),
          PopupMenuItem(value: _MoreAction.save, child: _menuRow(context, AIcons.checked, l10n.visibleRangeSaveAs)),
          PopupMenuItem(value: _MoreAction.reAddDefaults, child: _menuRow(context, AIcons.newTier, l10n.visibleRangeReAddDefaults)),
          const PopupMenuDivider(),
          PopupMenuItem(value: _MoreAction.lockDetailed, child: _menuRow(context, AIcons.locked, l10n.visibleRangeLockSheetTitle)),
          PopupMenuItem(value: _MoreAction.about, child: _menuRow(context, AIcons.info, l10n.visibleRangeAbout)),
        ],
      ),
    ];
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

  void _onCandidateTap(BuildContext context, FilterGridItem<VisibleRangeCandidateFilter> item) {
    final candidate = item.filter.candidate;
    final selection = context.read<Selection<FilterGridItem<VisibleRangeCandidateFilter>>>();
    if (selection.isSelecting) {
      if (candidate.rule != null) selection.toggleSelection(item);
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
              subtitle: Text(_kindLabel(context, rule.kind)),
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
    final l10n = context.l10n;
    final controller = TextEditingController(text: rule.label.startsWith('@') ? '' : rule.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.visibleRangeRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: visibleRangeRuleLabel(context, rule)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await _controller.updateRule(rule.copyWith(label: name));
    _browseSelection();
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
    await _controller.beginActivation(rule: rule, mode: mode, resultingFilters: target);
    if (!mounted) return;
    _browseSelection();
    await AvesNavItem(route: CollectionPage.routeName, filters: target).goTo(context, topLevel: false);
    await _controller.closeOpenSession(mediaSetTab.currentFilters ?? target);
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
    context.read<Selection<FilterGridItem<VisibleRangeCandidateFilter>>>().browse();
  }

  String _kindLabel(BuildContext context, VisibleRangeRuleKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      VisibleRangeRuleKind.restriction => l10n.visibleRangeRuleKindRestriction,
      VisibleRangeRuleKind.supplement => l10n.visibleRangeRuleKindSupplement,
    };
  }

  Future<void> _onMore(_MoreAction action) async {
    final l10n = context.l10n;
    switch (action) {
      case _MoreAction.addRestriction:
        await _addRule(VisibleRangeRuleKind.restriction);
      case _MoreAction.addSupplement:
        await _addRule(VisibleRangeRuleKind.supplement);
      case _MoreAction.saveBase:
        await _saveBaseFromCurrentFilters();
      case _MoreAction.order:
        await _pickOrder();
      case _MoreAction.save:
        await _saveRange();
      case _MoreAction.reAddDefaults:
        if (!_controller.canEdit) {
          _showBlocked();
          return;
        }
        final result = await _controller.reAddDefaultPresets();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.visibleRangeReAddDefaultsResult(result.added, result.skipped))));
      case _MoreAction.lockDetailed:
        await _lockDetailed();
      case _MoreAction.about:
        await _openAbout();
    }
  }

  Future<void> _addRule(VisibleRangeRuleKind kind) async {
    final l10n = context.l10n;
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    final filters = mediaSetTab.currentFilters;
    if (filters == null || filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.visibleRangeAddNoFilters)));
      return;
    }
    await _controller.addRule(kind: kind, filters: filters);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.visibleRangeRuleAdded)));
  }

  Future<void> _saveBaseFromCurrentFilters() async {
    final l10n = context.l10n;
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    final filters = mediaSetTab.currentFilters;
    if (filters == null || filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.visibleRangeAddNoFilters)));
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.visibleRangeSaveBaseTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _controller.saveBasePreset(name: name, filters: filters);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.visibleRangeBaseSaved)));
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

  Future<void> _saveRange() async {
    final l10n = context.l10n;
    final sessions = _controller.sessions.where((session) => session.hasChanges).toList();
    var chosen = '';
    if (sessions.isNotEmpty) {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) {
          var selected = '';
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(l10n.visibleRangeWriteBackTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.visibleRangeWriteBackHint),
                    ListTile(
                      title: Text(l10n.visibleRangeWriteBackNone),
                      trailing: Icon(selected.isEmpty ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      onTap: () => setDialogState(() => selected = ''),
                    ),
                    for (final session in sessions)
                      ListTile(
                        title: Text(_kindLabel(context, session.kind)),
                        subtitle: Text(l10n.visibleRangeWriteBackLine(_kindLabel(context, session.kind), session.added.length, session.removed.length)),
                        trailing: Icon(selected == session.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        onTap: () => setDialogState(() => selected = session.id),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
                TextButton(onPressed: () => Navigator.pop(context, selected), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
              ],
            ),
          );
        },
      );
      if (picked == null) return;
      chosen = picked;
    }
    if (chosen.isNotEmpty) {
      await _controller.writeBackSession(chosen);
    }
    await _controller.clearSessions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.visibleRangeSaved)));
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
