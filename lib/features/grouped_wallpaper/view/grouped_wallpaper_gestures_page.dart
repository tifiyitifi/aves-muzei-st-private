import 'dart:async';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_plan.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Binds the two wallpaper gestures to actions.
///
/// Mirrors Muzei's Gestures screen. Gestures are global: the bindings live in the
/// app metadata and travel in `state.json`, so the renderer acts on a tap even
/// while no page is mounted.
class GroupedWallpaperGesturesPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups/gestures';

  const new({super.key});

  @override
  State<GroupedWallpaperGesturesPage> createState() => _GroupedWallpaperGesturesPageState();
}

class _GroupedWallpaperGesturesPageState extends State<GroupedWallpaperGesturesPage> {
  GroupedWallpaperGestures _gestures = const GroupedWallpaperGestures();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final plan = await SavedGroupedWallpaperPlanStore().load();
    if (!mounted) return;
    setState(() {
      _gestures = plan.gestures;
      _loaded = true;
    });
  }

  Future<void> _apply(GroupedWallpaperGestures gestures) async {
    setState(() => _gestures = gestures);
    await SavedGroupedWallpaperPlanStore().setGestures(gestures);
    // The renderer reads the bindings from the state it already has: re-bake so
    // a gesture change applies without waiting for the next photo.
    await wallpaperEngineLink.prepare();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.wallpaperGroupGestures)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      l10n.wallpaperGroupGesturesHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  _GestureSection(
                    title: l10n.wallpaperGroupGesturesDoubleTap,
                    value: _gestures.doubleTap,
                    onChanged: (action) => unawaited(_apply(_gestures.copyWith(doubleTap: action))),
                  ),
                  const Divider(),
                  _GestureSection(
                    title: l10n.wallpaperGroupGesturesThreeFinger,
                    value: _gestures.threeFinger,
                    onChanged: (action) => unawaited(_apply(_gestures.copyWith(threeFinger: action))),
                  ),
                ],
              ),
            ),
    );
  }
}

class _GestureSection extends StatelessWidget {
  final String title;
  final GroupedWallpaperTapAction value;
  final ValueChanged<GroupedWallpaperTapAction> onChanged;

  const new({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ),
        RadioGroup<GroupedWallpaperTapAction>(
          groupValue: value,
          onChanged: (action) {
            if (action != null) onChanged(action);
          },
          child: Column(
            children: [
              for (final action in GroupedWallpaperTapAction.values)
                RadioListTile<GroupedWallpaperTapAction>(
                  value: action,
                  title: Text(_label(context, action)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(BuildContext context, GroupedWallpaperTapAction action) {
    final l10n = context.l10n;
    return switch (action) {
      GroupedWallpaperTapAction.none => l10n.wallpaperGroupTapNone,
      GroupedWallpaperTapAction.nextArtwork => l10n.wallpaperGroupTapNext,
      GroupedWallpaperTapAction.viewArtwork => l10n.wallpaperGroupTapView,
    };
  }
}
