import 'dart:async';

import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';
import 'package:aves/features/wallpaper_auto_advance/services/wallpaper_interval_options_controller.dart';
import 'package:aves/features/wallpaper_auto_advance/view/wallpaper_interval_label.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_add_dialog.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The shared interval picker used by both auto-advance pages.
///
/// The option list is global while [selected] stays owned by the caller (one
/// value per group, one for the Muzei wallpaper). A long press on a custom option
/// enters multi-select deletion; built-ins can only be cleared as a block with
/// 「Clear all intervals」 and restored with 「Add default intervals」.
class WallpaperIntervalOptionList extends StatefulWidget {
  final WallpaperAdvanceInterval selected;

  /// Writes the value to the caller's own setting. Never touches the catalog.
  final ValueChanged<WallpaperAdvanceInterval> onSelected;

  /// Injectable for tests; defaults to the app-wide controller.
  final WallpaperIntervalOptionsController? controller;

  const new({
    super.key,
    required this.selected,
    required this.onSelected,
    this.controller,
  });

  @override
  State<WallpaperIntervalOptionList> createState() => _WallpaperIntervalOptionListState();
}

class _WallpaperIntervalOptionListState extends State<WallpaperIntervalOptionList> {
  late final WallpaperIntervalOptionsController _controller = widget.controller ?? wallpaperIntervalOptionsController;

  bool _selecting = false;
  final Set<WallpaperAdvanceInterval> _selectedCustoms = {};

  @override
  void initState() {
    super.initState();
    unawaited(_controller.ensureLoaded());
  }

  void _enterSelection(WallpaperAdvanceInterval value) {
    setState(() {
      _selecting = true;
      _selectedCustoms
        ..clear()
        ..add(value);
    });
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selectedCustoms.clear();
    });
  }

  void _toggleCustom(WallpaperAdvanceInterval value) {
    setState(() {
      if (!_selectedCustoms.remove(value)) _selectedCustoms.add(value);
    });
  }

  Future<void> _add() async {
    final interval = await showWallpaperIntervalAddDialog(context, current: widget.selected);
    if (interval == null || !mounted) return;
    final actual = await _controller.addCustom(interval);
    if (!mounted) return;
    widget.onSelected(actual);
  }

  Future<void> _deleteSelected() async {
    if (_selectedCustoms.isEmpty) return;
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.wallpaperIntervalDeleteTitle,
      message: l10n.wallpaperIntervalDeleteMessage,
      ok: l10n.wallpaperIntervalDelete,
    );
    if (!confirmed || !mounted) return;
    final removed = Set<WallpaperAdvanceInterval>.of(_selectedCustoms);
    _cancelSelection();
    await _controller.deleteCustoms(removed);
  }

  Future<void> _resetAll() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.wallpaperIntervalResetAllTitle,
      message: l10n.wallpaperIntervalResetAllMessage,
      ok: l10n.wallpaperIntervalResetAll,
    );
    if (!confirmed || !mounted) return;
    await _controller.resetAll();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String ok,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: Text(ok),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final catalog = _controller.catalog;
        if (catalog == null) return const SizedBox.shrink();
        // After a Reset the list can be empty; still show the caller's current
        // value so the radio group always has a valid selection.
        final options = sorted([...catalog.options, widget.selected]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selecting) _buildSelectionBar(context) else _buildHints(context),
            if (_selecting) ..._buildSelectionOptions(context, catalog, options) else ..._buildRadioOptions(context, catalog, options),
            if (!_selecting) ..._buildFooter(context, catalog),
          ],
        );
      },
    );
  }

  Widget _buildHints(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.wallpaperIntervalOptionsHint, style: style),
          const SizedBox(height: 4),
          Text(l10n.wallpaperIntervalLongPressHint, style: style),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.wallpaperIntervalSelectedCount(_selectedCustoms.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: _selectedCustoms.isEmpty ? null : () => unawaited(_deleteSelected()),
            child: Text(l10n.wallpaperIntervalDelete),
          ),
          TextButton(
            onPressed: _cancelSelection,
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRadioOptions(BuildContext context, WallpaperIntervalCatalog catalog, List<WallpaperAdvanceInterval> options) {
    final l10n = context.l10n;
    return [
      RadioGroup<WallpaperAdvanceInterval>(
        groupValue: widget.selected,
        onChanged: (value) {
          if (value != null) widget.onSelected(value);
        },
        child: Column(
          children: [
            for (final option in options)
              ListTile(
                leading: Radio<WallpaperAdvanceInterval>(value: option),
                title: Text(wallpaperAdvanceIntervalLabel(context, option)),
                subtitle: catalog.isCustom(option) ? Text(l10n.wallpaperIntervalCustom) : null,
                onTap: () => widget.onSelected(option),
                onLongPress: () => _onLongPress(context, catalog, option),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildSelectionOptions(BuildContext context, WallpaperIntervalCatalog catalog, List<WallpaperAdvanceInterval> options) {
    final l10n = context.l10n;
    return [
      for (final option in options)
        if (catalog.isCustom(option))
          ListTile(
            leading: Checkbox(
              value: _selectedCustoms.contains(option),
              onChanged: (_) => _toggleCustom(option),
            ),
            title: Text(wallpaperAdvanceIntervalLabel(context, option)),
            subtitle: Text(l10n.wallpaperIntervalCustom),
            onTap: () => _toggleCustom(option),
          )
        else
          // Built-ins stay visible for context but take no part in the selection.
          ListTile(
            enabled: false,
            leading: const Icon(Icons.lock_outline),
            title: Text(wallpaperAdvanceIntervalLabel(context, option)),
            subtitle: Text(l10n.wallpaperIntervalBuiltIn),
          ),
    ];
  }

  List<Widget> _buildFooter(BuildContext context, WallpaperIntervalCatalog catalog) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return [
      const Divider(),
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(l10n.wallpaperIntervalAdd),
        onTap: () => unawaited(_add()),
      ),
      ListTile(
        enabled: catalog.missingDefaults.isNotEmpty,
        leading: const Icon(Icons.restore),
        title: Text(l10n.wallpaperIntervalAddDefaults),
        subtitle: Text(l10n.wallpaperIntervalAddDefaultsHint),
        onTap: () => unawaited(_controller.addMissingDefaults()),
      ),
      ListTile(
        leading: Icon(Icons.delete_sweep_outlined, color: theme.colorScheme.error),
        title: Text(l10n.wallpaperIntervalResetAll, style: TextStyle(color: theme.colorScheme.error)),
        subtitle: Text(l10n.wallpaperIntervalResetAllHint),
        onTap: () => unawaited(_resetAll()),
      ),
    ];
  }

  void _onLongPress(BuildContext context, WallpaperIntervalCatalog catalog, WallpaperAdvanceInterval option) {
    if (catalog.isCustom(option)) {
      _enterSelection(option);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.wallpaperIntervalBuiltInNotDeletable)),
      );
    }
  }
}
