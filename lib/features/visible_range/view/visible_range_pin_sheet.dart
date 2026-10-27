import 'dart:async';

import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_target_grid.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the unified "pin to visible range / wallpaper" sheet.
///
/// One confirmation writes the same filters to the cross product of the chosen
/// groups and targets, so arranging several surfaces takes a single visit. The
/// same confirmation can also write the filters back over the rules the user has
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
  final Set<VisibleRangeCandidateKind> _kinds = {VisibleRangeCandidateKind.restriction};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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
      setState(() {
        _targets = targets;
        _appliedTargets = applied;
        _selectedTargets.addAll([
          for (final target in targets)
            if (target.isGallery && !target.locked) target.rangeId,
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

  bool get _pinning => _kinds.isNotEmpty && _selectedTargets.isNotEmpty;

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
                kinds: {..._kinds},
                targetRangeIds: {..._selectedTargets},
              ),
            )
          : const VisibleRangePinResult(pinned: 0, skipped: 0);
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
                  _sectionLabel(context, l10n.visibleRangePinGroups),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in VisibleRangeCandidateKind.values)
                        FilterChip(
                          label: Text(_groupLabel(context, kind)),
                          selected: _kinds.contains(kind),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _kinds.add(kind);
                              } else {
                                _kinds.remove(kind);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  if (_kinds.isEmpty) _hint(context, l10n.visibleRangePinNoGroup),
                  const SizedBox(height: 20),
                  _sectionLabel(context, l10n.visibleRangePinTargets),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                  else
                    VisibleRangeTargetGrid(
                      targets: _targets,
                      selectedRangeIds: _selectedTargets,
                      onToggle: (target) {
                        setState(() {
                          if (!_selectedTargets.remove(target.rangeId)) {
                            _selectedTargets.add(target.rangeId);
                          }
                        });
                      },
                    ),
                  if (!_loading && _selectedTargets.isEmpty) _hint(context, l10n.visibleRangePinNoTarget),
                  const SizedBox(height: 20),
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

  String _groupLabel(BuildContext context, VisibleRangeCandidateKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      VisibleRangeCandidateKind.base => l10n.visibleRangePinGroupBase,
      VisibleRangeCandidateKind.restriction => l10n.visibleRangePinGroupRestriction,
      VisibleRangeCandidateKind.supplement => l10n.visibleRangePinGroupSupplement,
    };
  }
}
