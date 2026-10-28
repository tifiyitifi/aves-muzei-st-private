import 'dart:async';

import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_tile.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/selection_xor/selection_xor.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// Copies one group's effects to other groups.
///
/// A grid of group cards with the app-wide XOR-range gesture: a tap toggles one
/// group, a long press flips the interval from the last tapped group, so copying
/// to a run of groups is one gesture instead of many taps.
class GroupedWallpaperEffectsSyncPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups/effects/sync';

  /// The group the effects come from; it is never a copy target.
  final String sourceGroupId;
  final WallpaperEffectsConfig effects;
  final WallpaperGroupRangeController controller;

  const new({
    super.key,
    required this.sourceGroupId,
    required this.effects,
    required this.controller,
  });

  @override
  State<GroupedWallpaperEffectsSyncPage> createState() => _GroupedWallpaperEffectsSyncPageState();
}

class _GroupedWallpaperEffectsSyncPageState extends State<GroupedWallpaperEffectsSyncPage> {
  late final List<WallpaperGroup> _groups;
  late final Selection<WallpaperGroup> _selection;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groups = [
      for (final group in widget.controller.groups)
        if (group.id != widget.sourceGroupId) group,
    ];
    _selection = Selection<WallpaperGroup>(toSelectableItems: null);
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final ids = {
      for (final group in _groups)
        if (_selection.isSelected([group])) group.id,
    };
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.groupedWallpaperEffectsSyncEmpty)));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.setEffectsFor(ids, widget.effects);
      await wallpaperEngineLink.prepare();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.genericFailureFeedback)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupedWallpaperEffectsSyncTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l10n.groupedWallpaperEffectsSyncHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: _groups.isEmpty
                ? Center(child: Text(l10n.groupedWallpaperEffectsSyncEmpty))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const columns = 4;
                      const spacing = 8.0;
                      const padding = 12.0;
                      final width = (constraints.maxWidth - padding * 2 - spacing * (columns - 1)) / columns;
                      final height = width * 1.25;
                      return ListenableBuilder(
                        listenable: _selection,
                        builder: (context, _) => GridView.builder(
                          padding: const EdgeInsets.all(padding),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: spacing,
                            crossAxisSpacing: spacing,
                            childAspectRatio: width / height,
                          ),
                          itemCount: _groups.length,
                          itemBuilder: (context, index) {
                            final group = _groups[index];
                            return WallpaperGroupTile(
                              filter: WallpaperGroupFilter(
                                groupId: group.id,
                                number: group.number,
                                name: group.name,
                                description: group.description,
                                enabled: group.enabled,
                              ),
                              tileLayout: TileLayout.grid,
                              tileSize: Size(width, height),
                              selecting: true,
                              selected: _selection.isSelected([group]),
                              onTap: () => _selection.toggleSelection(group),
                              onLongPress: () => _selection.rangeXorTo(_groups, group),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => unawaited(_confirm()),
                  icon: const Icon(AIcons.copy),
                  label: Text(l10n.groupedWallpaperEffectsSync),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
