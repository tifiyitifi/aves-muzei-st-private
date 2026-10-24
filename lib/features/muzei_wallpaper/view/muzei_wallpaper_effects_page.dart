import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_overflow_button.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Edits the home and lock effect values.
///
/// Mirrors Muzei's Effects screen: the sliders apply to the live wallpaper
/// immediately, so the page debounces and lets the controller coalesce the
/// rebakes. Values are kept on Muzei's scales (`blur`/`grey` 0..500, `dim`
/// 0..255); the baker turns them into pixels, the renderer only crossfades.
class MuzeiWallpaperEffectsPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/effects';

  final WallpaperController controller;

  const new({
    super.key,
    required this.controller,
  });

  @override
  State<MuzeiWallpaperEffectsPage> createState() => _MuzeiWallpaperEffectsPageState();
}

class _MuzeiWallpaperEffectsPageState extends State<MuzeiWallpaperEffectsPage> {
  /// Keeps a slider drag from rebaking the wallpaper on every pixel step.
  static const _applyDelay = Duration(milliseconds: 300);

  late WallpaperEffectsConfig _effects;
  Timer? _timer;
  bool _editLock = false;
  bool _dirty = false;

  WallpaperController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _effects = _controller.prefs.effects;
  }

  @override
  void dispose() {
    // Flush a drag that was still waiting for the debounce.
    _apply();
    super.dispose();
  }

  void _update(WallpaperEffects value) {
    setState(() {
      _effects = _editLock && !_effects.link
          ? _effects.copyWith(lock: value)
          : _effects.copyWith(home: value);
      _dirty = true;
    });
    _timer?.cancel();
    _timer = Timer(_applyDelay, _apply);
  }

  void _apply() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    _dirty = false;
    unawaited(_controller.setEffects(_effects));
  }

  void _setLink(bool link) {
    setState(() {
      _effects = _effects.copyWith(link: link);
      if (link) _editLock = false;
      _dirty = true;
    });
    _apply();
  }

  void _reset() {
    setState(() {
      _effects = const WallpaperEffectsConfig();
      _dirty = true;
    });
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final linked = _effects.link;
        final editingLock = !linked && _editLock;
        final effects = editingLock ? _effects.lock : _effects.home;
        return AvesScaffold(
          appBar: AppBar(
            title: Text(l10n.muzeiWallpaperEffects),
            actions: [
              IconButton(
                tooltip: l10n.muzeiWallpaperEffectsReset,
                icon: const Icon(AIcons.restore),
                onPressed: _reset,
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              children: [
                if (_controller.baking) const LinearProgressIndicator(),
                if (!linked)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.muzeiWallpaperEffectsHome),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.muzeiWallpaperEffectsLock),
                        ),
                      ],
                      selected: {editingLock},
                      onSelectionChanged: (selection) => setState(() => _editLock = selection.first),
                    ),
                  ),
                _EffectSlider(
                  label: l10n.muzeiWallpaperEffectsBlur,
                  value: effects.blur.toDouble(),
                  max: WallpaperEffects.maxBlur.toDouble(),
                  onChanged: (value) => _update(effects.copyWith(blur: value.round())),
                ),
                _EffectSlider(
                  label: l10n.muzeiWallpaperEffectsDim,
                  value: effects.dim.toDouble(),
                  max: WallpaperEffects.maxDim.toDouble(),
                  onChanged: (value) => _update(effects.copyWith(dim: value.round())),
                ),
                _EffectSlider(
                  label: l10n.muzeiWallpaperEffectsGrey,
                  value: effects.grey.toDouble(),
                  max: WallpaperEffects.maxGrey.toDouble(),
                  onChanged: (value) => _update(effects.copyWith(grey: value.round())),
                ),
                SwitchListTile(
                  value: linked,
                  onChanged: _setLink,
                  title: Text(l10n.muzeiWallpaperEffectsLink),
                ),
              ],
            ),
          ),
          floatingActionButton: WallpaperOverflowFab(
            controller: _controller,
            section: WallpaperSection.effects,
          ),
        );
      },
    );
  }
}

class _EffectSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  const new({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                value.round().toString(),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          Slider(
            value: value,
            max: max,
            divisions: max.round(),
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
