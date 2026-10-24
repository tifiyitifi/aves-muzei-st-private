import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_gestures.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Binds the two wallpaper gestures to actions.
///
/// Mirrors Muzei's Gestures screen; the native engine reads the bindings from
/// `state.json`, so they also work while the app is not running.
class MuzeiWallpaperGesturesPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/gestures';

  final WallpaperController controller;

  const new({
    super.key,
    required this.controller,
  });

  @override
  State<MuzeiWallpaperGesturesPage> createState() => _MuzeiWallpaperGesturesPageState();
}

class _MuzeiWallpaperGesturesPageState extends State<MuzeiWallpaperGesturesPage> {
  late WallpaperGestures _gestures;

  WallpaperController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _gestures = _controller.prefs.gestures;
  }

  void _apply(WallpaperGestures gestures) {
    setState(() => _gestures = gestures);
    unawaited(_controller.setGestures(gestures));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.muzeiWallpaperGestures),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            _GestureSection(
              title: l10n.muzeiWallpaperGesturesDoubleTap,
              value: _gestures.doubleTap,
              onChanged: (action) => _apply(_gestures.copyWith(doubleTap: action)),
            ),
            const Divider(),
            _GestureSection(
              title: l10n.muzeiWallpaperGesturesThreeFinger,
              value: _gestures.threeFinger,
              onChanged: (action) => _apply(_gestures.copyWith(threeFinger: action)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GestureSection extends StatelessWidget {
  final String title;
  final WallpaperTapAction value;
  final ValueChanged<WallpaperTapAction> onChanged;

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
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        RadioGroup<WallpaperTapAction>(
          groupValue: value,
          onChanged: (action) {
            if (action != null) onChanged(action);
          },
          child: Column(
            children: [
              for (final action in WallpaperTapAction.values)
                RadioListTile<WallpaperTapAction>(
                  value: action,
                  title: Text(_label(context, action)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(BuildContext context, WallpaperTapAction action) {
    final l10n = context.l10n;
    return switch (action) {
      WallpaperTapAction.temporaryDisable => l10n.muzeiWallpaperTapTemporaryDisable,
      WallpaperTapAction.nextArtwork => l10n.muzeiWallpaperTapNextArtwork,
      WallpaperTapAction.viewArtwork => l10n.muzeiWallpaperTapViewArtwork,
      WallpaperTapAction.none => l10n.muzeiWallpaperTapNone,
    };
  }
}
