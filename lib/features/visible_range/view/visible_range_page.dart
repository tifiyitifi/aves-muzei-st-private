import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_nav.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
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
import 'package:aves/features/visible_range/view/widgets/visible_range_lock_dialog.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_rule_actions.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
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

  /// Whether the user put the wallpaper group page in their own navigation list.
  ///
  /// Such an entry is theirs to keep or remove from the navigation editor, so
  /// this page must not offer to bring a derived one back while it exists.
  bool get _wallpaperEntryPinned => settings.bottomNavigationActions.any((item) => item.route == GroupedWallpaperPage.routeName);

  /// What the page's single wallpaper entry offers right now.
  ///
  /// The entry is one toggle: it hides the bar's derived entry while that entry
  /// exists, and brings it back once the user closed it.
  WallpaperNavEntryAction get _wallpaperEntryAction => wallpaperNavEntryAction(
        mode: groupedWallpaperNavController.mode,
        entryClosed: groupedWallpaperNavController.entryClosed,
        pinned: _wallpaperEntryPinned,
      );

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
        return page;
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
      // The wallpaper groups own their own ranges, so they are reached from here
      // instead of a second filter page. One entry covers both directions: in
      // the shared mode the two pages are peers behind one entry, and with a
      // separate entry the same item closes or reopens that entry.
      _menuItem(
        context,
        _MoreAction.wallpaperGroups,
        AIcons.wallpaper,
        _wallpaperEntryAction == WallpaperNavEntryAction.close ? l10n.wallpaperGroupClose : l10n.wallpaperGroupOpen,
      ),
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

  Future<void> _selectBase(VisibleRangePreset? preset) async {
    if (!_canEdit) {
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
    if (!_canEdit) {
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
    if (!_canEdit) {
      _showBlocked();
      return;
    }
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
    final action = await showVisibleRangeRuleActions(context, rule: rule, canEdit: _canEdit);
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
      case _MoreAction.applyToMediaSet:
        await _applySelectionToMediaSet();
      case _MoreAction.order:
        await _pickOrder();
      case _MoreAction.reAddDefaults:
        if (!_canEdit) {
          _showBlocked();
          return;
        }
        final result = await _controller.reAddDefaultPresets();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeReAddDefaultsResult(result.added, result.skipped))));
      case _MoreAction.wallpaperGroups:
        await _openOrCloseWallpaperGroups();
      case _MoreAction.lockDetailed:
        await _lockDetailed();
      case _MoreAction.about:
        await _openAbout();
    }
  }

  /// Opens the wallpaper groups, or closes their bottom-bar entry.
  ///
  /// The merged menu item follows the bar: while the derived entry is shown it
  /// hides it, and while it is gone it brings the entry back before opening the
  /// page. The shared mode always opens, switching the shared destination so the
  /// bar keeps a single entry highlighted.
  Future<void> _openOrCloseWallpaperGroups() async {
    if (_wallpaperEntryAction == WallpaperNavEntryAction.close) {
      // Closing only hides the derived entry: the groups themselves are not
      // touched, and the bar keeps the visible-range entry the user is on.
      await groupedWallpaperNavController.setEntryClosed(true);
      return;
    }
    if (groupedWallpaperNavController.mode == GroupedWallpaperNavMode.shared) {
      visibleRangeDestination.value = VisibleRangeDestination.wallpaper;
      return;
    }
    if (groupedWallpaperNavController.entryClosed) {
      await groupedWallpaperNavController.setEntryClosed(false);
    }
    if (!mounted) return;
    await const AvesNavItem(route: GroupedWallpaperPage.routeName).goTo(context, topLevel: false);
  }

  Future<void> _pickOrder() async {
    if (!_canEdit) {
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

