import 'dart:async';

import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';
import 'package:aves/features/wallpaper_auto_advance/services/wallpaper_interval_options_controller.dart';
import 'package:aves/features/wallpaper_auto_advance/view/wallpaper_interval_label.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_add_sheet.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The shared interval picker used by both auto-advance pages.
///
/// The option list is global while [selected] stays owned by the caller (one
/// value per group, one for the Muzei wallpaper). A long press on any option
/// except Off enters multi-select deletion: built-in and custom options can both
/// be deleted, and only Off is pinned because it is the off switch.
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
  final Set<WallpaperAdvanceInterval> _selectedOptions = {};

  @override
  void initState() {
    super.initState();
    unawaited(_controller.ensureLoaded());
  }

  void _enterSelection(WallpaperAdvanceInterval value) {
    setState(() {
      _selecting = true;
      _selectedOptions
        ..clear()
        ..add(value);
    });
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selectedOptions.clear();
    });
  }

  void _toggleOption(WallpaperAdvanceInterval value) {
    setState(() {
      if (!_selectedOptions.remove(value)) _selectedOptions.add(value);
    });
  }

  Future<void> _add() async {
    final interval = await showWallpaperIntervalAddSheet(context, current: widget.selected);
    if (interval == null || !mounted) return;
    final actual = await _controller.addCustom(interval);
    if (!mounted) return;
    widget.onSelected(actual);
  }

  Future<void> _deleteSelected() async {
    if (_selectedOptions.isEmpty) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(l10n.wallpaperIntervalDeleteTitle),
          content: Text(l10n.wallpaperIntervalDeleteMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: Text(l10n.wallpaperIntervalDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final removed = Set<WallpaperAdvanceInterval>.of(_selectedOptions);
    _cancelSelection();
    await _controller.deleteOptions(removed);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final catalog = _controller.catalog;
        if (catalog == null) return const SizedBox.shrink();
        // After a Clear the list can be empty; still show the caller's current
        // value so the radio group always has a valid selection.
        final options = sorted([...catalog.options, widget.selected]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selecting) _buildSelectionBar(context),
            if (_selecting) ..._buildSelectionOptions(context, catalog, options) else ..._buildRadioOptions(context, catalog, options),
            if (!_selecting) ..._buildAddOption(context),
          ],
        );
      },
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
              l10n.wallpaperIntervalSelectedCount(_selectedOptions.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: _selectedOptions.isEmpty ? null : () => unawaited(_deleteSelected()),
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
                subtitle: _subtitle(context, catalog, option),
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
        if (option.isOff || !catalog.contains(option))
          // Off is pinned (it is the off switch) and a value that only survives
          // as the caller's current selection is not an option of the list at
          // all: both stay visible for context but take no part in the selection.
          ListTile(
            enabled: false,
            leading: const Icon(Icons.lock_outline),
            title: Text(wallpaperAdvanceIntervalLabel(context, option)),
            subtitle: option.isOff ? null : Text(l10n.wallpaperIntervalCurrent),
          )
        else
          ListTile(
            leading: Checkbox(
              value: _selectedOptions.contains(option),
              onChanged: (_) => _toggleOption(option),
            ),
            title: Text(wallpaperAdvanceIntervalLabel(context, option)),
            subtitle: Text(catalog.isCustom(option) ? l10n.wallpaperIntervalCustom : l10n.wallpaperIntervalBuiltIn),
            onTap: () => _toggleOption(option),
          ),
    ];
  }

  /// Tags the row: a value that is not in the list only survives as the caller's
  /// current selection (after Clear all), and built-ins have no tag at all.
  Widget? _subtitle(BuildContext context, WallpaperIntervalCatalog catalog, WallpaperAdvanceInterval option) {
    final l10n = context.l10n;
    if (!catalog.contains(option)) return Text(l10n.wallpaperIntervalCurrent);
    if (catalog.isCustom(option)) return Text(l10n.wallpaperIntervalCustom);
    return null;
  }

  List<Widget> _buildAddOption(BuildContext context) {
    final l10n = context.l10n;
    return [
      const Divider(),
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(l10n.wallpaperIntervalAdd),
        onTap: () => unawaited(_add()),
      ),
    ];
  }

  void _onLongPress(BuildContext context, WallpaperIntervalCatalog catalog, WallpaperAdvanceInterval option) {
    if (option.isOff) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.wallpaperIntervalOffNotDeletable)),
      );
    } else if (catalog.contains(option)) {
      _enterSelection(option);
    }
    // Otherwise the value only survives as the caller's current selection: it is
    // not an option of the list, so there is nothing to delete.
  }
}
