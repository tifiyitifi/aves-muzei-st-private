import 'dart:async';

import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/features/selection_xor/selection_xor.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:material_ui/material_ui.dart';

/// Every file batch processing still holds, newest first.
///
/// The page is database-driven: what it lists is exactly what the app recorded,
/// so a file dropped into the folder by another app is never replaced or moved
/// by these actions. Selection follows the app-wide XOR-range rule.
class BatchResultsPage extends StatefulWidget {
  static const routeName = '/settings/batch/results';

  final BatchResultsService service;

  const new({super.key, this.service = batchResultsService});

  @override
  State<BatchResultsPage> createState() => _BatchResultsPageState();
}

enum _ResultsAction { selectAll, selectNone, replace, moveBack, keep }

class _BatchResultsPageState extends State<BatchResultsPage> {
  final Selection<BatchResult> _selection = Selection(toSelectableItems: null, keyOf: (result) => result.id);

  List<BatchResult>? _results;
  Map<String, AvesEntry> _entries = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _selection
      ..removeListener(_onSelectionChanged)
      ..dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    // A result deleted from the album is normal browsing; its row must not keep
    // offering actions for a file that no longer exists.
    await widget.service.pruneMissingResults();
    final store = await widget.service.store();
    final results = await store.getResults();
    final entries = results.isEmpty ? <AvesEntry>{} : await localMediaDb.loadEntriesByUris(results.map((result) => result.resultUri).toSet());
    if (!mounted) return;
    setState(() {
      _results = results;
      _entries = {for (final entry in entries) entry.uri: entry};
    });
    final keys = results.map((result) => result.id).toSet();
    final stale = _selection.selectedItems.where((result) => !keys.contains(result.id)).toList(growable: false);
    if (stale.isNotEmpty) _selection.removeFromSelection(stale);
  }

  List<BatchResult> get _orderedResults => _results ?? const [];

  List<BatchResult> get _targets => _selection.selectedItems.isEmpty ? _orderedResults : _selection.selectedItems.toList(growable: false);

  Future<void> _onAction(_ResultsAction action) async {
    switch (action) {
      case _ResultsAction.selectAll:
        _selection.addToSelection(_orderedResults);
      case _ResultsAction.selectNone:
        _selection.browse();
      case _ResultsAction.replace:
        await _replace();
      case _ResultsAction.moveBack:
        await _moveBack();
      case _ResultsAction.keep:
        _selection.browse();
    }
  }

  Future<void> _replace() async {
    final l10n = context.l10n;
    final targets = _targets.where((result) => result.canReplaceSource).toList(growable: false);
    if (targets.isEmpty) return;
    if (!await _confirm(l10n.batchResultsReplaceConfirmTitle, l10n.batchResultsReplaceConfirmBody(targets.length))) return;

    setState(() => _busy = true);
    try {
      final replaced = await widget.service.replaceWithSource(targets);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(replaced > 0 ? l10n.batchResultsReplaced(replaced) : l10n.batchResultsActionFailed)),
      );
      _selection.browse();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveBack() async {
    final l10n = context.l10n;
    final targets = _targets.where((result) => result.canMoveBack).toList(growable: false);
    if (targets.isEmpty) return;
    if (!await _confirm(l10n.batchResultsMoveBackConfirmTitle, l10n.batchResultsMoveBackConfirmBody(targets.length))) return;

    setState(() => _busy = true);
    try {
      final moved = await widget.service.moveBack(targets);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(moved > 0 ? l10n.batchResultsMoved(moved) : l10n.batchResultsActionFailed)),
      );
      _selection.browse();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancelTooltip)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.applyButtonLabel)),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openEntry(BatchResult result) async {
    final entry = _entries[result.resultUri];
    if (entry == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: EntryViewerPage.routeName),
        builder: (_) => EntryViewerPage(initialEntry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    final selecting = _selection.isSelecting;
    final selected = _selection.selectedItems;
    final canAct = _targets.any((result) => result.canReplaceSource);

    return AvesScaffold(
      appBar: AppBar(
        leading: selecting ? IconButton(icon: const Icon(Icons.close), onPressed: _selection.browse) : null,
        title: Text(selecting ? l10n.batchResultsSelectedCount(selected.length) : l10n.batchResultsPageTitle),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            PopupMenuButton<_ResultsAction>(
              icon: const Icon(Icons.more_vert),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onSelected: (action) => unawaited(_onAction(action)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ResultsAction.selectAll,
                  enabled: results != null && results.isNotEmpty && selected.length < results.length,
                  child: _menuRow(Icons.select_all, l10n.menuActionSelectAll),
                ),
                if (selecting) PopupMenuItem(value: _ResultsAction.selectNone, child: _menuRow(Icons.deselect, l10n.menuActionSelectNone)),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _ResultsAction.replace,
                  enabled: canAct,
                  child: _menuRow(Icons.published_with_changes, l10n.batchResultsReplace),
                ),
                PopupMenuItem(
                  value: _ResultsAction.moveBack,
                  enabled: _targets.any((result) => result.canMoveBack),
                  child: _menuRow(Icons.drive_file_move_outline, l10n.batchResultsMoveBack),
                ),
                if (selecting) PopupMenuItem(value: _ResultsAction.keep, child: _menuRow(Icons.visibility_outlined, l10n.batchResultsNotNow)),
              ],
            ),
        ],
      ),
      body: results == null
          ? const Center(child: CircularProgressIndicator())
          : results.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.batchResultsEmpty, textAlign: .center),
              ),
            )
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) => _buildRow(context, results[index]),
            ),
    );
  }

  Widget _buildRow(BuildContext context, BatchResult result) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    const extent = 56.0;
    final selected = _selection.isSelected([result]);
    final entry = _entries[result.resultUri];
    final createdAt = formatDateTime(result.createdAt, settings.avesLocale, MediaQuery.alwaysUse24HourFormatOf(context));
    final source = result.canMoveBack ? l10n.batchResultsSource(result.sourceDirectory) : l10n.batchResultsUnknownSource;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: extent,
          child: entry != null ? ThumbnailImage(entry: entry, extent: extent, devicePixelRatio: MediaQuery.devicePixelRatioOf(context)) : Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      title: Text(result.resultFileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.batchResultsSubtitle(source, _statusLabel(context, result.status), createdAt), maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: selected,
      trailing: _selection.isSelecting ? Checkbox(value: selected, onChanged: (_) => _selection.toggleSelection(result)) : null,
      onTap: () => _selection.isSelecting ? _selection.toggleSelection(result) : unawaited(_openEntry(result)),
      onLongPress: () => _selection.rangeXorTo(_orderedResults, result),
    );
  }

  String _statusLabel(BuildContext context, BatchResultStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      BatchResultStatus.pending => l10n.batchResultsStatusPending,
      BatchResultStatus.applied => l10n.batchResultsStatusApplied,
      BatchResultStatus.discarded => l10n.batchResultsStatusDiscarded,
    };
  }

  Widget _menuRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );
}
