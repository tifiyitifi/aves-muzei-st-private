import 'dart:async';

import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:aves/features/refra_edit/services/refra_edit_service.dart';
import 'package:aves/features/selection_xor/selection_xor.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/media/enums.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Every file the copy-first editor is still holding, newest first.
///
/// The page is database-driven: rows describe what the app recorded, so what it lists is exactly
/// what it can still move back, copy back or delete. Selection follows the app-wide XOR-range rule,
/// and every bulk action lives in the overflow menu.
class RefraEditRecordsPage extends StatefulWidget {
  static const routeName = '/settings/refra_edit/records';

  const new({super.key});

  @override
  State<RefraEditRecordsPage> createState() => _RefraEditRecordsPageState();
}

enum _RecordsAction { selectAll, selectNone, moveBack, copyBack, delete, clear }

class _RefraEditRecordsPageState extends State<RefraEditRecordsPage> {
  final Selection<RefraEditRecord> _selection = Selection(toSelectableItems: null, keyOf: (record) => record.key);

  List<RefraEditRecordItem>? _items;
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
    final items = await refraEditService.records();
    if (!mounted) return;
    setState(() => _items = items);
    // A record deleted elsewhere must not stay selected.
    final keys = items.map((item) => item.record.key).toSet();
    final stale = _selection.selectedItems.where((record) => !keys.contains(record.key)).toList(growable: false);
    if (stale.isNotEmpty) _selection.removeFromSelection(stale);
  }

  List<RefraEditRecord> get _orderedRecords => [for (final item in _items ?? const <RefraEditRecordItem>[]) item.record];

  Future<void> _onAction(_RecordsAction action) async {
    switch (action) {
      case _RecordsAction.selectAll:
        _selection.addToSelection(_orderedRecords);
      case _RecordsAction.selectNone:
        _selection.browse();
      case _RecordsAction.moveBack:
        await _transfer(copy: false);
      case _RecordsAction.copyBack:
        await _transfer(copy: true);
      case _RecordsAction.delete:
        await _deleteSelected();
      case _RecordsAction.clear:
        await _clear();
    }
  }

  Future<void> _transfer({required bool copy}) async {
    final l10n = context.l10n;
    final selected = _selection.selectedItems.toList(growable: false);
    if (selected.isEmpty) return;
    if (selected.any((record) => !record.canTransferBack)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refraEditTransferUnavailable)));
      return;
    }

    final strategy = await _resolveConflict(selected);
    if (strategy == null || !mounted) return;

    setState(() => _busy = true);
    var success = true;
    for (final group in groupBy(selected, (record) => record.sessionId).values) {
      final session = group.first.session;
      if (session == null) {
        success = false;
        continue;
      }
      success =
          await refraEditService.transferBack(
            session,
            outputKeys: group.map((record) => record.key).toSet(),
            copy: copy,
            nameConflictStrategy: strategy,
          ) &&
          success;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(copy ? l10n.refraEditCopyBackFailed : l10n.refraEditMoveBackFailed)),
      );
    }
    _selection.browse();
    await _load();
  }

  /// Asks how to handle names that already exist in the records' source folders.
  ///
  /// One dialog covers every selected folder: the strategy applies to the whole transfer, and the
  /// message names the first conflicting directory so the choice is not blind.
  Future<NameConflictStrategy?> _resolveConflict(List<RefraEditRecord> records) async {
    final l10n = context.l10n;
    final byDirectory = groupBy(records.where((record) => record.canTransferBack), (record) => record.sourceDirectory);
    var conflictCount = 0;
    String? firstDirectory;
    for (final entry in byDirectory.entries) {
      final conflicts = await refraEditService.conflictingNames(entry.key, entry.value.map((record) => record.fileName));
      if (conflicts.isEmpty) continue;
      conflictCount += conflicts.length;
      firstDirectory ??= entry.key;
    }
    if (conflictCount == 0 || firstDirectory == null || !mounted) return NameConflictStrategy.rename;
    return showDialog<NameConflictStrategy>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.refraEditConflictTitle),
        content: Text(l10n.refraEditConflictBody(conflictCount, firstDirectory!)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelTooltip)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(NameConflictStrategy.rename),
            child: Text(l10n.nameConflictStrategyRename),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(NameConflictStrategy.replace),
            child: Text(l10n.nameConflictStrategyReplace),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final l10n = context.l10n;
    final selected = _selection.selectedItems.toList(growable: false);
    if (selected.isEmpty) return;
    if (!await _confirm(l10n.refraEditDeleteSelectedConfirmTitle, l10n.refraEditDeleteSelectedConfirmBody)) return;

    setState(() => _busy = true);
    final success = await refraEditService.deleteRecords(selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refraEditDiscardFailed)));
    }
    _selection.browse();
    await _load();
  }

  Future<void> _clear() async {
    final l10n = context.l10n;
    if (!await _confirm(l10n.refraEditClearRecords, l10n.refraEditClearRecordsConfirm)) return;

    setState(() => _busy = true);
    final success = await refraEditService.clearRecords();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refraEditClearRecordsFailed)));
    }
    _selection.browse();
    await _load();
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
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.deleteButtonLabel)),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openEntry(RefraEditRecordItem item) async {
    final entry = item.entry;
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
    final items = _items;
    final selecting = _selection.isSelecting;
    final selected = _selection.selectedItems;
    final canTransfer = selected.isNotEmpty && selected.every((record) => record.canTransferBack);

    return AvesScaffold(
      appBar: AppBar(
        leading: selecting ? IconButton(icon: const Icon(Icons.close), onPressed: _selection.browse) : null,
        title: Text(selecting ? l10n.refraEditRecordCount(selected.length) : l10n.refraEditRecordListTitle),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            PopupMenuButton<_RecordsAction>(
              icon: const Icon(Icons.more_vert),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onSelected: (action) => unawaited(_onAction(action)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _RecordsAction.selectAll,
                  enabled: items != null && items.isNotEmpty && selected.length < items.length,
                  child: _menuRow(Icons.select_all, l10n.menuActionSelectAll),
                ),
                if (selecting)
                  PopupMenuItem(
                    value: _RecordsAction.selectNone,
                    child: _menuRow(Icons.deselect, l10n.menuActionSelectNone),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _RecordsAction.moveBack,
                  enabled: canTransfer,
                  child: _menuRow(Icons.drive_file_move_outline, l10n.refraEditMoveSelectedBack),
                ),
                PopupMenuItem(
                  value: _RecordsAction.copyBack,
                  enabled: canTransfer,
                  child: _menuRow(Icons.copy_all_outlined, l10n.refraEditCopySelectedBack),
                ),
                PopupMenuItem(
                  value: _RecordsAction.delete,
                  enabled: selected.isNotEmpty,
                  child: _menuRow(Icons.delete_outline, l10n.refraEditDeleteSelected),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _RecordsAction.clear,
                  enabled: items != null && items.isNotEmpty,
                  child: _menuRow(Icons.delete_sweep_outlined, l10n.refraEditClearRecords),
                ),
              ],
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.refraEditRecordEmpty, textAlign: .center),
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _buildRow(context, items[index]),
            ),
    );
  }

  Widget _buildRow(BuildContext context, RefraEditRecordItem item) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final record = item.record;
    const extent = 56.0;
    final selected = _selection.isSelected([record]);
    final source = record.canTransferBack ? l10n.refraEditSessionSource(record.sourceDirectory) : l10n.refraEditRecordUnknownSource;
    final createdAt = formatDateTime(record.createdAt, settings.avesLocale, MediaQuery.alwaysUse24HourFormatOf(context));

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: extent,
          child: item.entry != null
              ? ThumbnailImage(
                  entry: item.entry!,
                  extent: extent,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                )
              : Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      title: Text(record.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$source · ${_kindLabel(context, record.kind)} · $createdAt',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: selected,
      trailing: _selection.isSelecting ? Checkbox(value: selected, onChanged: (_) => _selection.toggleSelection(record)) : null,
      onTap: () => _selection.isSelecting ? _selection.toggleSelection(record) : unawaited(_openEntry(item)),
      onLongPress: () => _selection.rangeXorTo(_orderedRecords, record),
    );
  }

  String _kindLabel(BuildContext context, RefraEditOutputKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      RefraEditOutputKind.staged => l10n.refraEditRecordKindStaged,
      RefraEditOutputKind.builtIn => l10n.refraEditRecordKindBuiltIn,
      RefraEditOutputKind.external => l10n.refraEditRecordKindExternal,
      RefraEditOutputKind.unknown => l10n.refraEditRecordKindUnknown,
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
