import 'dart:async';

import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_counter.dart';
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_chip.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// The visible-range page: the same chip-grid language as the album page, but a
/// tap changes the browsing condition instead of opening a collection.
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

class _VisibleRangePageState extends State<VisibleRangePage> {
  final Set<String> _selection = {};
  ({int? base, int? intermediate, int? total})? _counts;
  int _countToken = 0;

  VisibleRangeController get _controller => visibleRangeController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.init());
    unawaited(_refreshCount());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => unawaited(_refreshCount());

  Future<void> _refreshCount() async {
    final token = ++_countToken;
    final counts = await VisibleRangeCounter.counts(_controller.gallery);
    if (!mounted || token != _countToken) return;
    setState(() => _counts = counts);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final l10n = context.l10n;
        final range = _controller.gallery;
        final selecting = _selection.isNotEmpty;
        return AvesScaffold(
          appBar: selecting
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_selection.clear),                  ),
                  title: Text(l10n.visibleRangeSelectionCount(_selection.length)),
                  actions: [
                    if (_selection.length == 1)
                      IconButton(
                        icon: const Icon(AIcons.edit),
                        tooltip: l10n.visibleRangeActionRename,
                        onPressed: () => _editSelected(range),
                      ),
                    IconButton(
                      icon: const Icon(AIcons.delete),
                      tooltip: l10n.visibleRangeActionDelete,
                      onPressed: _deleteSelected,
                    ),
                  ],
                )
              : AppBar(
                  title: Text(l10n.visibleRangePageTitle),
                  actions: [
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
                        PopupMenuItem(value: _MoreAction.addRestriction, child: _menuRow(context, AIcons.titleFilter, l10n.visibleRangeAddRestriction)),
                        PopupMenuItem(value: _MoreAction.addSupplement, child: _menuRow(context, AIcons.show, l10n.visibleRangeAddSupplement)),
                        PopupMenuItem(value: _MoreAction.saveBase, child: _menuRow(context, AIcons.folder, l10n.visibleRangeSaveBase)),
                        const PopupMenuDivider(),
                        PopupMenuItem(value: _MoreAction.order, child: _menuRow(context, AIcons.sortOrder, l10n.visibleRangeOrder)),
                        PopupMenuItem(value: _MoreAction.save, child: _menuRow(context, AIcons.checked, l10n.visibleRangeSaveAs)),
                        PopupMenuItem(value: _MoreAction.reAddDefaults, child: _menuRow(context, AIcons.newTier, l10n.visibleRangeReAddDefaults)),
                        const PopupMenuDivider(),
                        PopupMenuItem(value: _MoreAction.lockDetailed, child: _menuRow(context, AIcons.locked, l10n.visibleRangeLockSheetTitle)),
                        PopupMenuItem(
                          value: _MoreAction.about,
                          child: _menuRow(context, AIcons.info, l10n.visibleRangeAbout),
                        ),
                      ],
                    ),
                  ],
                ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _buildBaseSection(context, range),
                const SizedBox(height: 20),
                _buildRuleSection(context, range, VisibleRangeRuleKind.restriction),
                const SizedBox(height: 20),
                _buildRuleSection(context, range, VisibleRangeRuleKind.supplement),
                const SizedBox(height: 24),
                _buildSummaryCard(context, range),
                const SizedBox(height: 16),
                _buildNotes(context, range),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: range.locked ? l10n.visibleRangeUnlock : l10n.visibleRangeLock,
            onPressed: _toggleLock,
            child: Icon(range.locked ? AIcons.unlocked : AIcons.locked),
          ),
        );
      },
    );
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

  // sections

  Widget _buildSummaryCard(BuildContext context, VisibleRange range) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final restricted = range.isRestricted;
    final conditions = _conditions(context, range);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.visibleRangeSectionCurrent, style: theme.textTheme.titleMedium),
              ),
              Text(
                restricted ? l10n.visibleRangeRestricted : l10n.visibleRangeUnrestricted,
                style: theme.textTheme.labelLarge?.copyWith(color: restricted ? colors.error : colors.primary),
              ),
            ],
          ),
          if (_counts?.total != null) ...[
            const SizedBox(height: 4),
            Text(l10n.visibleRangeCount(_counts!.total!), style: theme.textTheme.bodyMedium),
          ],
          if (range.locked) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(AIcons.locked, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text(l10n.visibleRangeLockedReadOnly, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
              ],
            ),
          ],
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final condition in conditions)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('· $condition', style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  /// Human-readable list of every active condition, in evaluation order.
  List<String> _conditions(BuildContext context, VisibleRange range) {
    final l10n = context.l10n;
    final result = <String>[
      '${l10n.visibleRangeRuleKindBase}: ${_baseLabel(context, range)}',
    ];
    for (final kind in range.order.isIntersectFirst
        ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement]
        : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction]) {
      for (final rule in range.activeRulesOf(kind)) {
        result.add('${_kindLabel(context, kind)}: ${_ruleLabel(context, rule)}');
      }
    }
    return result;
  }

  Widget _buildBaseSection(BuildContext context, VisibleRange range) {
    final l10n = context.l10n;
    final presets = _controller.presets;
    return _Section(
      title: l10n.visibleRangeSectionBase,
      count: _counts?.base,
      children: [
        VisibleRangeChip(
          label: l10n.visibleRangeUnrestricted,
          icon: AIcons.filterOff,
          selected: range.isBaseUnrestricted,
          locked: !_controller.canEdit,
          onTap: () => _selectBase(null),
        ),
        for (final preset in presets)
          VisibleRangeChip(
            label: _presetLabel(context, preset),
            icon: AIcons.folder,
            selected: !range.isBaseUnrestricted && range.basePresetId == preset.id,
            locked: !_controller.canEdit,
            onTap: () => _selectBase(preset),
            onLongPress: preset.builtin ? null : () => _deletePreset(preset),
          ),
      ],
    );
  }

  Widget _buildRuleSection(BuildContext context, VisibleRange range, VisibleRangeRuleKind kind) {
    final l10n = context.l10n;
    final rules = range.rulesOf(kind);
    return _Section(
      title: switch (kind) {
        VisibleRangeRuleKind.restriction => l10n.visibleRangeSectionRestrictions,
        VisibleRangeRuleKind.supplement => range.order.isIntersectFirst ? l10n.visibleRangeSectionSupplementsOutside : l10n.visibleRangeSectionSupplementsInside,
      },
      // The step count belongs to the group evaluated last: restrictions in
      // intersect-first, supplements in union-first.
      count: kind == VisibleRangeRuleKind.restriction
          ? (range.order.isIntersectFirst ? _counts?.intermediate : _counts?.total)
          : (range.order.isIntersectFirst ? _counts?.total : _counts?.intermediate),
      children: [
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l10n.visibleRangeAddNoFilters, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        for (final rule in rules)
          VisibleRangeChip(
            label: _ruleLabel(context, rule),
            detail: rule.active ? l10n.visibleRangeRuleSummary(_kindLabel(context, kind), rule.filters.length) : l10n.visibleRangeRuleInactive,
            icon: kind == VisibleRangeRuleKind.restriction ? AIcons.titleFilter : AIcons.show,
            active: rule.active,
            selected: _selection.contains(rule.id),
            locked: !_controller.canEdit,
            onTap: () => _onRuleTap(rule),
            onLongPress: () => _onRuleLongPress(rule),
          ),
      ],
    );
  }

  Widget _buildNotes(BuildContext context, VisibleRange range) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.visibleRangeOrderHint, style: style),
        const SizedBox(height: 8),
        Text(l10n.visibleRangeRestrictedHint, style: style),
      ],
    );
  }

  // labels

  String _kindLabel(BuildContext context, VisibleRangeRuleKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      VisibleRangeRuleKind.restriction => l10n.visibleRangeRuleKindRestriction,
      VisibleRangeRuleKind.supplement => l10n.visibleRangeRuleKindSupplement,
    };
  }

  String _presetLabel(BuildContext context, VisibleRangePreset preset) {
    if (!preset.builtin) return preset.name;
    final l10n = context.l10n;
    return switch (preset.name) {
      'visibleRangePresetImage' => l10n.visibleRangePresetImage,
      'visibleRangePresetVideo' => l10n.visibleRangePresetVideo,
      'visibleRangePresetNotVideo' => l10n.visibleRangePresetNotVideo,
      'visibleRangePresetFavourite' => l10n.visibleRangePresetFavourite,
      'visibleRangePresetRating5' => l10n.visibleRangePresetRating5,
      'visibleRangePresetRating4' => l10n.visibleRangePresetRating4,
      'visibleRangePresetRating3' => l10n.visibleRangePresetRating3,
      'visibleRangePresetPortrait' => l10n.visibleRangePresetPortrait,
      'visibleRangePresetLandscape' => l10n.visibleRangePresetLandscape,
      'visibleRangePresetPanorama' => l10n.visibleRangePresetPanorama,
      'visibleRangePresetRaw' => l10n.visibleRangePresetRaw,
      'visibleRangePresetMotionPhoto' => l10n.visibleRangePresetMotionPhoto,
      _ => preset.name,
    };
  }

  String _ruleLabel(BuildContext context, VisibleRangeRule rule) {
    final label = rule.effectiveLabel;
    if (label.isNotEmpty) return label;
    return context.l10n.visibleRangeRuleKindSupplement;
  }

  String _baseFilterLabel(BuildContext context, Set<CollectionFilter> filters) {
    return filters.map((filter) => filter.getLabel(context)).join(' · ');
  }

  /// The base's display name: 「不限」, the localized preset name, or the custom
  /// name the user saved.
  String _baseLabel(BuildContext context, VisibleRange range) {
    final l10n = context.l10n;
    if (range.isBaseUnrestricted) return l10n.visibleRangeUnrestricted;
    final preset = _controller.presets.firstWhereOrNull((v) => v.id == range.basePresetId);
    if (preset != null) return _presetLabel(context, preset);
    if (range.baseName.isNotEmpty) return range.baseName;
    return _baseFilterLabel(context, range.baseFilters);
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

  void _onRuleTap(VisibleRangeRule rule) {
    if (_selection.isNotEmpty) {
      setState(() => _selection.contains(rule.id) ? _selection.remove(rule.id) : _selection.add(rule.id));
      return;
    }
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    unawaited(_controller.toggleRule(rule.id));
  }

  void _onRuleLongPress(VisibleRangeRule rule) {
    setState(() => _selection.contains(rule.id) ? _selection.remove(rule.id) : _selection.add(rule.id));
  }

  void _editSelected(VisibleRange range) {
    final id = _selection.firstOrNull;
    if (id == null) return;
    final rule = range.ruleById(id);
    if (rule == null) return;
    unawaited(_showRuleEditor(rule));
  }

  /// Single-rule actions. Locked rules show only read-only actions.
  Future<void> _showRuleEditor(VisibleRangeRule rule) async {
    final l10n = context.l10n;
    final editable = _controller.canEdit;
    final action = await showModalBottomSheet<_RuleAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(rule.effectiveLabel.isEmpty ? _kindLabel(context, rule.kind) : rule.effectiveLabel),
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
              leading: const Icon(AIcons.titleFilter),
              title: Text(l10n.visibleRangeActionMoveToRestriction),
              enabled: editable && rule.kind != VisibleRangeRuleKind.restriction,
              onTap: () => Navigator.pop(context, _RuleAction.moveToRestriction),
            ),
            ListTile(
              leading: const Icon(AIcons.show),
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
        await _controller.deleteRules({rule.id});
    }
  }

  Future<void> _renameRule(VisibleRangeRule rule) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: rule.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.visibleRangeRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: rule.effectiveLabel),
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
  }

  Future<void> _moveRule(VisibleRangeRule rule, VisibleRangeRuleKind kind) async {
    if (rule.kind == kind) return;
    final range = _controller.gallery;
    final position = range.rulesOf(kind).length;
    await _controller.updateRule(rule.copyWith(kind: kind, position: position));
  }

  Future<void> _moveRuleToBase(VisibleRangeRule rule) async {
    final label = rule.effectiveLabel;
    await _controller.selectBase(presetId: '', name: label, filters: rule.filters);
    await _controller.deleteRules({rule.id});
  }

  Future<void> _activate(VisibleRangeRule rule, VisibleRangeActivationMode mode) async {
    final current = mediaSetTab.currentFilters ?? const <CollectionFilter>{};
    final target = mode == VisibleRangeActivationMode.override ? rule.filters : {...current, ...rule.filters};
    await _controller.beginActivation(rule: rule, mode: mode, resultingFilters: target);
    if (!mounted) return;
    setState(_selection.clear);
    await AvesNavItem(route: CollectionPage.routeName, filters: target).goTo(context, topLevel: false);
    await _controller.closeOpenSession(mediaSetTab.currentFilters ?? target);
  }

  Future<void> _deleteSelected() async {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    final l10n = context.l10n;
    final count = _selection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.visibleRangeDeleteConfirm(count)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.deleteRules({..._selection});
    setState(_selection.clear);
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
        await Navigator.maybeOf(context)?.push(
          MaterialPageRoute(settings: const RouteSettings(name: VisibleRangeAboutPage.routeName), builder: (_) => const VisibleRangeAboutPage()),
        );
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
}

enum _RuleAction { rename, moveToRestriction, moveToSupplement, moveToBase, activateReplace, activateAppend, delete }

class _Section extends StatelessWidget {
  final String title;
  final int? count;
  final List<Widget> children;

  const new({required this.title, this.count, required this.children});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            if (count != null)
              Text(
                l10n.visibleRangeCount(count!),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
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
