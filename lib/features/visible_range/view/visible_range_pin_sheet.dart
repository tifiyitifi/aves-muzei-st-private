import 'dart:async';

import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_target_grid.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the unified "pin to visible range / wallpaper" sheet.
///
/// One confirmation writes the same filters to the cross product of the chosen
/// targets, so arranging several surfaces takes a single visit. The same
/// confirmation can also write the filters back over the rules the user has
/// opened a media set with.
Future<VisibleRangePinResult?> showVisibleRangePinSheet(BuildContext context, {required Set<CollectionFilter> filters}) {
  final description = formatDateTime(DateTime.now(), settings.avesLocale, MediaQuery.alwaysUse24HourFormatOf(context));
  return showModalBottomSheet<VisibleRangePinResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => VisibleRangePinSheet(
      filters: filters,
      initialName: visibleRangeFilterLabels(context, filters),
      initialDescription: description,
    ),
  );
}

class VisibleRangePinSheet extends StatefulWidget {
  final Set<CollectionFilter> filters;
  final String initialName;
  final String initialDescription;

  const new({
    super.key,
    required this.filters,
    required this.initialName,
    required this.initialDescription,
  });

  @override
  State<VisibleRangePinSheet> createState() => _VisibleRangePinSheetState();
}

class _VisibleRangePinSheetState extends State<VisibleRangePinSheet> {
  late final TextEditingController _nameController = TextEditingController(text: widget.initialName);
  late final TextEditingController _descriptionController = TextEditingController(text: widget.initialDescription);
  List<VisibleRangePinTarget> _targets = const [];
  List<VisibleRangeWriteBackTarget> _appliedTargets = const [];
  final Set<String> _selectedTargets = {};
  final Set<String> _selectedUsages = {};
  VisibleRangeInjectionMode _injection = VisibleRangeInjectionMode.auto;
  VisibleRangeRuleKind? _forcedRole;
  VisibleRangePinWriteMode _writeMode = VisibleRangePinWriteMode.append;
  bool _rememberInjection = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _injection = visibleRangeController.pinInjectionRemembered ? visibleRangeController.pinInjectionMode : VisibleRangeInjectionMode.auto;
    _rememberInjection = visibleRangeController.pinInjectionRemembered;
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// The targets and the write-back list are read once per open, so a group
  /// created a moment ago is already selectable.
  Future<void> _load() async {
    try {
      final targets = await visibleRangeController.loadPinTargets();
      final applied = await visibleRangeController.loadAppliedTargets();
      if (!mounted) return;
      // A locked setup accepts no new content: the gallery lock freezes every
      // gallery target, and the wallpaper lock freezes every wallpaper group.
      final groupLocked = wallpaperLockService.groupSwitchLocked;
      final galleryLocked = visibleRangeController.locked;
      setState(() {
        _targets = [
          for (final target in targets)
            target.copyWith(locked: target.locked || (target.isGallery ? galleryLocked : groupLocked)),
        ];
        _appliedTargets = [for (final target in applied) target.copyWith(locked: target.locked || (target.isGallery ? galleryLocked : groupLocked))];
        _selectedTargets.addAll([
          for (final target in _targets)
            if (target.kind == VisibleRangePinTargetKind.galleryGroup && target.rangeId == visibleRangeController.currentGalleryGroupId && !target.locked) target.id,
        ]);
        _loading = false;
      });
    } on StateError {
      // The controller is not initialized (a test or a very early open): an
      // empty sheet is better than a crash, and confirming stays disabled.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool get _pinning => _selectedTargets.isNotEmpty;

  bool get _draftGroupTargetSelected =>
      (visibleRangeController.targetSource?.targetsAreDraft ?? false) && _targets.any((target) => target.isWallpaperGroup && _selectedTargets.contains(target.id));

  bool get _canConfirm => !_busy && (_pinning || _selectedUsages.isNotEmpty);

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    setState(() => _busy = true);
    try {
      final pinResult = _pinning
          ? await visibleRangeController.pinFilters(
              VisibleRangePinRequest(
                filters: widget.filters,
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                targetIds: {..._selectedTargets},
                injection: _injection,
                forcedRole: _forcedRole,
                writeMode: _writeMode,
              ),
            )
          : const VisibleRangePinResult(pinned: 0, skipped: 0);
      if (_rememberInjection) {
        await visibleRangeController.setPinInjection(mode: _injection, remembered: true);
      }
      final writeBack = await visibleRangeController.writeBackTargets(
        usageIds: {..._selectedUsages},
        filters: widget.filters,
        baseName: _nameController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        VisibleRangePinResult(
          pinned: pinResult.pinned,
          skipped: pinResult.skipped,
          written: writeBack.written,
          writeSkipped: writeBack.skipped,
        ),
      );
    } on StateError {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeManagementBlocked)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final galleryGroups = _targets.where((target) => target.kind == VisibleRangePinTargetKind.galleryGroup).toList();
    final outsideTargets = _targets.where((target) => target.kind == VisibleRangePinTargetKind.outside).toList();
    final wallpaperGroups = _targets.where((target) => target.kind == VisibleRangePinTargetKind.wallpaperGroup).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 0),
            child: Text(l10n.visibleRangePinTitle, style: theme.textTheme.titleLarge),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(context, l10n.visibleRangePinFilters),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in widget.filters)
                        AvesFilterChip(
                          filter: filter,
                          showLeading: true,
                          showText: true,
                          allowGenericIcon: true,
                          useFilterColor: false,
                          heroType: HeroType.never,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.visibleRangePinName,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.visibleRangePinDescription,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(context, l10n.visibleRangePinGroupGallery),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                  else ...[
                    if (galleryGroups.isNotEmpty)
                      VisibleRangeTargetGrid(
                        targets: galleryGroups,
                        selectedTargetIds: _selectedTargets,
                        onToggle: _toggleTarget,
                      ),
                    if (outsideTargets.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _sectionLabel(context, l10n.visibleRangePinGroupOutside),
                      VisibleRangeTargetGrid(
                        targets: outsideTargets,
                        selectedTargetIds: _selectedTargets,
                        onToggle: _toggleTarget,
                      ),
                    ],
                    if (wallpaperGroups.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionLabel(context, l10n.visibleRangePinGroupWallpaper),
                      VisibleRangeTargetGrid(
                        targets: wallpaperGroups,
                        selectedTargetIds: _selectedTargets,
                        onToggle: _toggleTarget,
                      ),
                    ],
                  ],
                  if (!_loading && _selectedTargets.isEmpty) _hint(context, l10n.visibleRangePinNoTarget),
                  if (!_loading && _draftGroupTargetSelected) _hint(context, l10n.wallpaperGroupDraftHint),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(l10n.visibleRangePinInjection),
                    subtitle: Text(l10n.visibleRangePinInjectionHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    children: [
                      SegmentedButton<VisibleRangeInjectionMode>(
                        segments: [
                          ButtonSegment(value: VisibleRangeInjectionMode.auto, label: Text(l10n.visibleRangePinInjectionAuto)),
                          ButtonSegment(value: VisibleRangeInjectionMode.enable, label: Text(l10n.visibleRangePinInjectionEnable)),
                          ButtonSegment(value: VisibleRangeInjectionMode.park, label: Text(l10n.visibleRangePinInjectionPark)),
                        ],
                        selected: {_injection},
                        onSelectionChanged: (selection) => setState(() => _injection = selection.first),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rememberInjection,
                        title: Text(l10n.visibleRangePinRemember),
                        onChanged: (value) => setState(() => _rememberInjection = value),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.visibleRangePinRole),
                        subtitle: Text(_forcedRole == null ? l10n.visibleRangePinRoleAuto : _roleLabel(context, _forcedRole!)),
                        trailing: PopupMenuButton<VisibleRangeRuleKind?>(
                          onSelected: (value) => setState(() => _forcedRole = value),
                          itemBuilder: (context) => [
                            PopupMenuItem(value: null, child: Text(l10n.visibleRangePinRoleAuto)),
                            for (final role in VisibleRangeRuleKind.values) PopupMenuItem(value: role, child: Text(_roleLabel(context, role))),
                          ],
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.visibleRangePinWriteMode),
                        subtitle: Text(_writeMode == VisibleRangePinWriteMode.append ? l10n.visibleRangePinWriteAppend : l10n.visibleRangePinWriteReplace),
                        trailing: Switch(
                          value: _writeMode == VisibleRangePinWriteMode.replace,
                          onChanged: (value) => setState(() => _writeMode = value ? VisibleRangePinWriteMode.replace : VisibleRangePinWriteMode.append),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _sectionLabel(context, l10n.visibleRangeWriteBackSection),
                  Text(l10n.visibleRangeWriteBackHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  if (!_loading && _appliedTargets.isEmpty)
                    Text(l10n.visibleRangeWriteBackEmpty, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                  else
                    for (final target in _appliedTargets)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selectedUsages.contains(target.usageId),
                        enabled: !target.locked,
                        title: Text(visibleRangeWriteBackTargetLabel(context, target)),
                        subtitle: Text(visibleRangeWriteBackTargetLine(context, target)),
                        onChanged: target.locked
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedUsages.add(target.usageId);
                                  } else {
                                    _selectedUsages.remove(target.usageId);
                                  }
                                });
                              },
                      ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canConfirm ? () => unawaited(_confirm()) : null,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.visibleRangePinConfirm),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleTarget(VisibleRangePinTarget target) {
    setState(() {
      if (!_selectedTargets.remove(target.id)) {
        _selectedTargets.add(target.id);
      }
    });
  }

  String _roleLabel(BuildContext context, VisibleRangeRuleKind role) {
    final l10n = context.l10n;
    return switch (role) {
      VisibleRangeRuleKind.source => l10n.visibleRangePinGroupBase,
      VisibleRangeRuleKind.restriction => l10n.visibleRangePinGroupRestriction,
      VisibleRangeRuleKind.supplement => l10n.visibleRangePinGroupSupplement,
    };
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _hint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
    );
  }
}
