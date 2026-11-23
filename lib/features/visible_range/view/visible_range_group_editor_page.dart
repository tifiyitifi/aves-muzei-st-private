import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_apply.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_editor_session.dart';
import 'package:aves/features/visible_range/view/visible_range_action_delegate.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_rule_actions.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/behaviour/pop/scope.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/scaling.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Edits one gallery group: its base range, restrictions and supplements.
///
/// The page works on a draft, like the wallpaper group page: closing asks to
/// save or discard, and nothing is written until the user saves. The group's own
/// conditions are the only thing here; the scope-wide outside pool stays on the
/// visible-range page. Group 0 (「Unrestricted」) has nothing to edit and is
/// refused before the page opens.
class VisibleRangeGroupEditorPage extends StatefulWidget {
  static const routeName = '/visible_range/group_editor';

  final String groupId;

  const new({super.key, required this.groupId});

  @override
  State<VisibleRangeGroupEditorPage> createState() => _VisibleRangeGroupEditorPageState();
}

enum _EditorMenu { save, discard, editRule, order, applyToMediaSet }

enum _EditorClose { discard, save }

class _VisibleRangeGroupEditorPageState extends State<VisibleRangeGroupEditorPage> {
  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final _selection = Selection<FilterGridItem<VisibleRangeCandidateFilter>>(toSelectableItems: null);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  VisibleRangeCandidateStats? _resultStats;
  int _resultToken = 0;
  VisibleRange? _stored;
  VisibleRange? _draft;

  VisibleRangeController get _controller => visibleRangeController;

  bool get _dirty => _draft != null && _draft != _stored;

  @override
  void initState() {
    super.initState();
    final group = _controller.galleryGroupById(widget.groupId);
    _stored = group;
    // A draft survives a bottom-bar visit: the session owns it, the page renders
    // it. Reopening a page whose draft was already discarded starts clean.
    _draft = visibleRangeEditorSession.draft ?? group;
    unawaited(_refreshStats());
    unawaited(_refreshResultStats());
  }

  @override
  void dispose() {
    _selection.dispose();
    _appBarHeightNotifier.dispose();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    final draft = _draft;
    if (draft == null) return;
    final filtersByKey = <String, Set<CollectionFilter>>{};
    for (final section in buildVisibleRangeSections(range: draft)) {
      for (final candidate in section.candidates) {
        if (candidate.placeholder) continue;
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

  /// Count and cover of what the draft resolves to.
  ///
  /// The result preview is the draft's own result, not the media type: it is the
  /// same stat the range page shows for the group once the draft is saved.
  Future<void> _refreshResultStats() async {
    final draft = _draft;
    final token = ++_resultToken;
    if (draft == null) {
      setState(() => _resultStats = null);
      return;
    }
    final filter = draft.resolve(outside: _controller.outside);
    final filters = filter == null ? const <CollectionFilter>{} : <CollectionFilter>{filter};
    final stats = await VisibleRangeCandidateStatsLoader.load([filters]);
    if (!mounted || token != _resultToken) return;
    setState(() => _resultStats = stats.values.firstOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final l10n = context.l10n;
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.visibleRangeGroupEditorTitle)),
        body: Center(child: Text(l10n.visibleRangeNoCandidates)),
      );
    }
    final source = context.read<CollectionSource>();
    final sections = _buildSections(context, draft);
    final items = sections.values.expand((list) => list).where((item) => !item.filter.summary && item.filter.candidate.rule != null).toList();
    final delegate = VisibleRangeActionDelegate(
      controller: _controller,
      settingsRouteKey: VisibleRangePage.routeName,
      itemBuilder: () => items,
      onRename: (context, rule) => _renameRule(rule),
      onDelete: (context, rules) => _deleteRules(rules),
      onActivate: (context, rule) => _activate(rule, VisibleRangeActivationMode.override),
      extraLayoutRows: (context) => const [],
    );
    final page = FilterGroupProvider(
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
                  title: _groupName(context, draft),
                  titleStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                    fontWeight: FontWeight.normal,
                    letterSpacing: 0,
                    fontFeatures: const [],
                  ),
                  actionDelegate: delegate,
                  extraActionsBuilder: _buildExtraActions,
                  extraMenuEntriesBuilder: _buildExtraMenuEntries,
                  onExtraMenuSelected: (value) {
                    if (value is _EditorMenu) unawaited(_onMenuSelected(value));
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
                emptyBuilder: () => Center(child: Text(l10n.visibleRangeNoCandidates)),
                heroType: HeroType.never,
                onTileTap: (item, navigate) => _onTileTap(item),
                selectableItem: (item) => !item.filter.summary && item.filter.candidate.isApplicable,
                tileBuilder: _buildTile,
                footerBuilder: null,
              ),
            );
          },
        ),
      ),
    );
    return AvesPopScope(
      handlers: [
        APopHandler(
          canPop: (context) => !_dirty,
          onPopBlocked: (context) => unawaited(_close()),
        ),
      ],
      child: page,
    );
  }

  String _groupName(BuildContext context, VisibleRange group) {
    final name = group.name;
    if (name.startsWith('@')) return visibleRangePresetLabel(context, name.substring(1));
    if (name.isNotEmpty) return name;
    final number = _controller.galleryGroupNumber(group.id);
    return number > 0 ? context.l10n.wallpaperGroupFallbackName(number) : context.l10n.visibleRangeUnrestricted;
  }

  Map<ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>> _buildSections(BuildContext context, VisibleRange draft) {
    final result = <ChipSectionKey, List<FilterGridItem<VisibleRangeCandidateFilter>>>{};
    for (final section in buildVisibleRangeSections(range: draft)) {
      final countText = switch (section.kind) {
        VisibleRangeCandidateKind.base => '${section.candidates.where((candidate) => !candidate.isUnrestricted).length}',
        VisibleRangeCandidateKind.restriction || VisibleRangeCandidateKind.supplement => '${section.candidates.where((candidate) => candidate.active).length}/${section.candidates.length}',
      };
      final candidates = section.kind == VisibleRangeCandidateKind.base || section.candidates.isNotEmpty ? section.candidates : [_emptyCandidate(section.kind)];
      result[VisibleRangeSectionKey(context, section.kind, countText: countText)] = [
        for (final candidate in candidates) FilterGridItem(VisibleRangeCandidateFilter(candidate), null),
      ];
    }
    final active = buildVisibleRangeActiveCandidates(range: draft, outside: _controller.outside);
    result[VisibleRangeActiveSectionKey(context, restricted: draft.isRestricted(outside: _controller.outside))] = [
      for (final candidate in active) FilterGridItem(VisibleRangeCandidateFilter(candidate, summary: true), null),
    ];
    return result;
  }

  VisibleRangeCandidate _emptyCandidate(VisibleRangeCandidateKind kind) => VisibleRangeCandidate(
    id: 'editor.empty.${kind.name}',
    kind: kind,
    filters: const {},
    labelKey: 'visibleRangeSectionEmpty',
    placeholder: true,
  );

  Widget _buildTile(BuildContext context, FilterGridItem<VisibleRangeCandidateFilter> item, Size tileSize) {
    final candidate = item.filter.candidate;
    return MetaData(
      metaData: ScalerMetadata(item),
      child: ListenableBuilder(
        listenable: _selection,
        builder: (context, _) => VisibleRangeTile(
          gridItem: item,
          stats: candidate.isGallery ? _resultStats : _stats[candidate.statsKey],
          tileLayout: settings.getTileLayout(VisibleRangePage.routeName),
          tileSize: tileSize,
          summary: item.filter.summary,
          showStateIcon: !candidate.isGallery,
          selectable: !item.filter.summary && candidate.isApplicable,
          selecting: _selection.isSelecting,
          selected: _selection.selectedItems.contains(item),
          onTap: () => _onTileTap(item),
        ),
      ),
    );
  }

  void _onTileTap(FilterGridItem<VisibleRangeCandidateFilter> item) {
    final candidate = item.filter.candidate;
    if (_selection.isSelecting) {
      if (candidate.isApplicable) _selection.toggleSelection(item);
      return;
    }
    if (candidate.isUnrestricted) {
      _clearSources();
      return;
    }
    final rule = candidate.rule;
    if (rule != null) _toggleRule(rule);
  }

  void _updateDraft(VisibleRange next) {
    visibleRangeEditorSession.setDraft(next);
    setState(() => _draft = next);
    unawaited(_refreshStats());
    unawaited(_refreshResultStats());
  }

  void _toggleRule(VisibleRangeRule rule) {
    final draft = _draft;
    if (draft == null) return;
    _updateDraft(
      draft.copyWith(rules: [for (final candidate in draft.rules) candidate.id == rule.id ? candidate.copyWith(active: !candidate.active) : candidate]),
    );
  }

  void _clearSources() {
    final draft = _draft;
    if (draft == null) return;
    _updateDraft(draft.copyWith(rules: draft.rules.where((rule) => rule.kind != VisibleRangeRuleKind.source).toList()));
  }

  Future<void> _renameRule(VisibleRangeRule rule) async {
    final l10n = context.l10n;
    final nameController = TextEditingController(text: rule.label.startsWith('@') ? '' : rule.label);
    final descriptionController = TextEditingController(text: rule.description);
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.visibleRangeEditNameDescription),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.visibleRangePinName, hintText: visibleRangeRuleLabel(context, rule)),
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
    if (result == null) return;
    final draft = _draft;
    if (draft == null) return;
    _updateDraft(
      draft.copyWith(
        rules: [for (final candidate in draft.rules) candidate.id == rule.id ? candidate.copyWith(label: result.name, description: result.description) : candidate],
      ),
    );
    _browseSelection();
  }

  Future<void> _deleteRules(Set<VisibleRangeRule> rules) async {
    if (rules.isEmpty) return;
    final draft = _draft;
    if (draft == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.visibleRangeDeleteConfirm(rules.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    _updateDraft(draft.copyWith(rules: draft.rules.where((rule) => !rules.map((r) => r.id).contains(rule.id)).toList()));
    _browseSelection();
  }

  Future<void> _activate(VisibleRangeRule rule, VisibleRangeActivationMode mode) async {
    final draft = _draft;
    if (draft == null) return;
    _browseSelection();
    await applyVisibleRangeCandidates(
      context,
      rangeId: draft.id,
      candidates: [VisibleRangeCandidate.fromRule(rule)],
      replace: mode == VisibleRangeActivationMode.override,
    );
  }

  void _browseSelection() {
    if (!mounted) return;
    _selection.browse();
  }

  List<Widget> _buildExtraActions(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection,
    VisibleRangeActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      if (!settings.useTvLayout) return const [];
      final rule = _selectedRule(selection);
      return [
        if (rule != null)
          IconButton(
            icon: const Icon(AIcons.edit),
            tooltip: context.l10n.visibleRangeEditRule,
            onPressed: () => unawaited(_showRuleEditor(rule)),
          ),
        if (selection.selectedItemCount > 0)
          IconButton(
            icon: const Icon(AIcons.apply),
            tooltip: context.l10n.visibleRangeApplyToMediaSet,
            onPressed: () => unawaited(_applySelectionToMediaSet()),
          ),
      ];
    }
    final closeButton = IconButton(
      icon: const Icon(Icons.close),
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: () => unawaited(_close()),
    );
    if (!settings.useTvLayout) return [closeButton];
    return [
      closeButton,
      PopupMenuButton<_EditorMenu>(
        icon: const Icon(AIcons.more),
        tooltip: context.l10n.visibleRangeMore,
        onSelected: (action) => unawaited(_onMenuSelected(action)),
        itemBuilder: _menuEntries,
      ),
    ];
  }

  List<PopupMenuEntry<Object>> _buildExtraMenuEntries(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection,
    VisibleRangeActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      final rule = _selectedRule(selection);
      return [
        if (rule != null)
          PopupMenuItem<Object>(
            value: _EditorMenu.editRule,
            child: Row(children: [const Icon(AIcons.edit, size: 20), const SizedBox(width: 12), Text(context.l10n.visibleRangeEditRule)]),
          ),
        if (selection.selectedItemCount > 0)
          PopupMenuItem<Object>(
            value: _EditorMenu.applyToMediaSet,
            child: Row(children: [const Icon(AIcons.apply, size: 20), const SizedBox(width: 12), Text(context.l10n.visibleRangeApplyToMediaSet)]),
          ),
      ];
    }
    return _menuEntries(context);
  }

  List<PopupMenuEntry<_EditorMenu>> _menuEntries(BuildContext context) {
    final l10n = context.l10n;
    return [
      PopupMenuItem(
        value: _EditorMenu.save,
        enabled: _dirty,
        child: Row(children: [const Icon(Icons.check, size: 20), const SizedBox(width: 12), Text(l10n.visibleRangeGroupSaveChanges)]),
      ),
      PopupMenuItem(
        value: _EditorMenu.discard,
        enabled: _dirty,
        child: Row(children: [const Icon(AIcons.cancel, size: 20), const SizedBox(width: 12), Text(l10n.visibleRangeGroupDiscardChanges)]),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _EditorMenu.order,
        child: Row(children: [const Icon(AIcons.sortOrder, size: 20), const SizedBox(width: 12), Text(l10n.visibleRangeOrder)]),
      ),
    ];
  }

  Future<void> _onMenuSelected(_EditorMenu action) async {
    switch (action) {
      case _EditorMenu.save:
        await _save();
      case _EditorMenu.discard:
        final stored = _stored;
        if (stored != null) {
          visibleRangeEditorSession.setDraft(stored);
          setState(() => _draft = stored);
          unawaited(_refreshResultStats());
        }
      case _EditorMenu.editRule:
        final rule = _selectedRule(_selection);
        if (rule != null) await _showRuleEditor(rule);
      case _EditorMenu.order:
        await _pickOrder();
      case _EditorMenu.applyToMediaSet:
        await _applySelectionToMediaSet();
    }
  }

  VisibleRangeRule? _selectedRule(Selection<FilterGridItem<VisibleRangeCandidateFilter>> selection) {
    if (!selection.isSelecting) return null;
    final items = selection.selectedItems;
    if (items.length != 1) return null;
    return items.first.filter.candidate.rule;
  }

  /// Single-rule actions on the draft.
  Future<void> _showRuleEditor(VisibleRangeRule rule) async {
    final action = await showVisibleRangeRuleActions(context, rule: rule, canEdit: true);
    if (!mounted || action == null) return;
    switch (action) {
      case VisibleRangeRuleAction.rename:
        await _renameRule(rule);
      case VisibleRangeRuleAction.moveToRestriction:
        _moveRule(rule, VisibleRangeRuleKind.restriction);
      case VisibleRangeRuleAction.moveToSupplement:
        _moveRule(rule, VisibleRangeRuleKind.supplement);
      case VisibleRangeRuleAction.moveToBase:
        _moveRule(rule, VisibleRangeRuleKind.source);
      case VisibleRangeRuleAction.activateReplace:
        await _activate(rule, VisibleRangeActivationMode.override);
      case VisibleRangeRuleAction.activateAppend:
        await _activate(rule, VisibleRangeActivationMode.append);
      case VisibleRangeRuleAction.delete:
        await _deleteRules({rule});
    }
  }

  void _moveRule(VisibleRangeRule rule, VisibleRangeRuleKind kind) {
    final draft = _draft;
    if (draft == null || rule.kind == kind) return;
    _updateDraft(
      draft.copyWith(
        rules: [
          for (final candidate in draft.rules)
            candidate.id == rule.id ? candidate.copyWith(kind: kind, position: draft.rulesOf(kind).length) : candidate,
        ],
      ),
    );
    _browseSelection();
  }

  Future<void> _applySelectionToMediaSet() async {
    if (!_selection.isSelecting) return;
    final draft = _draft;
    if (draft == null) return;
    final candidates = [
      for (final item in _selection.selectedItems)
        if (!item.filter.summary && item.filter.candidate.isApplicable) item.filter.candidate,
    ];
    if (candidates.isEmpty) return;
    _browseSelection();
    await applyVisibleRangeCandidates(context, rangeId: draft.id, candidates: candidates);
  }

  Future<void> _pickOrder() async {
    final draft = _draft;
    if (draft == null) return;
    final l10n = context.l10n;
    final order = await showDialog<VisibleRangeOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.visibleRangeOrder),
        children: [
          for (final value in VisibleRangeOrder.values)
            ListTile(
              title: Text(value.isIntersectFirst ? l10n.visibleRangeOrderIntersectFirst : l10n.visibleRangeOrderUnionFirst),
              trailing: value == draft.order ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (order == null || !mounted) return;
    _updateDraft(draft.copyWith(order: order));
  }

  /// Persists the draft. Returns false when the group refuses the write.
  Future<bool> _save() async {
    final draft = _draft;
    if (draft == null) return false;
    if (!_controller.canEditGroup(draft.id)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeManagementBlocked)));
      return false;
    }
    await _controller.saveGalleryGroup(draft);
    if (!mounted) return false;
    final stored = _controller.galleryGroupById(draft.id);
    if (stored == null) {
      // The group was deleted while the page was open: saving cannot resurrect it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeGroupMissing)));
      return false;
    }
    visibleRangeEditorSession.setDraft(stored);
    setState(() {
      _stored = stored;
      _draft = stored;
    });
    unawaited(_refreshResultStats());
    return true;
  }

  Future<void> _close() async {
    if (!await _confirmClose()) return;
    if (!mounted) return;
    visibleRangeEditorSession.close();
    switch (groupedWallpaperNavController.mode) {
      case GroupedWallpaperNavMode.shared:
        visibleRangeDestination.value = VisibleRangeDestination.range;
      case GroupedWallpaperNavMode.separateLeft:
      case GroupedWallpaperNavMode.separateRight:
        final navigator = Navigator.maybeOf(context);
        if (navigator?.canPop() == true) {
          navigator!.pop();
        } else {
          await const AvesNavItem(route: VisibleRangePage.routeName).goTo(context, topLevel: true);
        }
    }
  }

  Future<bool> _confirmClose() async {
    if (!_dirty) return true;
    final l10n = context.l10n;
    final choice = await showDialog<_EditorClose>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.visibleRangeGroupCloseConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, _EditorClose.discard), child: Text(l10n.visibleRangeGroupDiscardChanges)),
          TextButton(onPressed: () => Navigator.pop(context, _EditorClose.save), child: Text(l10n.visibleRangeGroupSaveChanges)),
        ],
      ),
    );
    switch (choice) {
      case null:
        return false;
      case _EditorClose.discard:
        return true;
      case _EditorClose.save:
        return _save();
    }
  }
}
