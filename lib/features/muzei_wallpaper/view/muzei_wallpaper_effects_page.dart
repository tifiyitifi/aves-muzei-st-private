import 'dart:async';
import 'dart:ui' as ui;

import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/view/slot_artwork_image.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_overflow_button.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Edits the home and lock effect values, with a live preview of the result.
///
/// Muzei's effects screen has no preview of its own: its "live" feedback comes
/// from the system wallpaper preview, where the effects screen floats over the
/// running wallpaper engine. This port bakes its wallpapers ahead of time, so a
/// rebake takes hundreds of milliseconds and can never follow a slider. The
/// preview therefore applies the very same math on the GPU (`ImageFiltered`,
/// `ColorFiltered`, and the dim curve), which is instant, while the debounced
/// bake still updates the real wallpaper.
///
/// Values keep Muzei's scales (`blur`/`grey` 0..500, `dim` 0..255). Our own
/// defaults are all zero, unlike Muzei's 250/128/0; see [WallpaperEffects].
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

class _MuzeiWallpaperEffectsPageState extends State<MuzeiWallpaperEffectsPage> with SingleTickerProviderStateMixin {
  /// Keeps a slider drag from rebaking the wallpaper on every pixel step.
  static const _applyDelay = Duration(milliseconds: 300);

  late final TabController _tabs;
  late WallpaperEffectsConfig _effects;
  Timer? _timer;
  bool _dirty = false;

  WallpaperController get _controller => widget.controller;

  bool get _editingLock => _tabs.index == 1;

  /// The values on screen: the surface being edited, honouring the link toggle.
  WallpaperEffects get _currentEffects => _editingLock ? _effects.effectiveLock : _effects.home;

  @override
  void initState() {
    super.initState();
    _effects = _controller.prefs.effects;
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    // Flush a drag that was still waiting for the debounce.
    _apply();
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  void _update(WallpaperEffects value) {
    setState(() {
      _effects = _appliedToCurrent(value);
      _dirty = true;
    });
    _timer?.cancel();
    _timer = Timer(_applyDelay, _apply);
  }

  /// Stores [value] on the surface being edited.
  WallpaperEffectsConfig _appliedToCurrent(WallpaperEffects value) {
    return _effects.applyTo(onLock: _editingLock, value: value);
  }

  void _apply() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    _dirty = false;
    unawaited(_controller.setEffects(_effects));
  }

  /// Applies a preset to the edited surface and bakes it right away: presets are
  /// deliberate choices, not slider drags, so there is nothing to debounce.
  void _applyPreset(WallpaperEffects preset) {
    setState(() {
      _effects = _appliedToCurrent(preset);
      _dirty = true;
    });
    _apply();
  }

  void _setLink(bool link) {
    setState(() {
      _effects = _effects.withLink(linked: link, fromLock: _editingLock);
      _dirty = true;
    });
    _apply();
  }

  Widget? _artwork() {
    final slot = _controller.current;
    final file = _controller.currentFile;
    if (slot == null || file == null) return null;
    return Image(
      image: SlotArtworkImage(file: file, contentKey: slot.artwork.entryId),
      key: ValueKey('effects-preview-${slot.id}-${slot.artwork.entryId}'),
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }

  /// Applies the effects to the preview on the GPU.
  ///
  /// Same math as the baker, so what the sliders show is what the next bake
  /// writes: the sigma is relative to the display height (the bake targets the
  /// wallpaper height) and the dim uses the artwork's own darkness.
  Widget _preview(BuildContext context, Widget artwork) {
    final effects = _currentEffects;
    final darkness = _controller.current?.artwork.darkness ?? 0.5;
    final sigma = effects.sigmaFor(MediaQuery.sizeOf(context).height);

    Widget child = artwork;
    if (effects.grey > 0) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(effects.desaturationMatrix),
        child: child,
      );
    }
    if (sigma > 0) {
      child = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp),
        child: child,
      );
    }
    final dimAlpha = effects.dimAlpha(darkness);
    if (dimAlpha > 0) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          ColoredBox(color: Colors.black.withValues(alpha: dimAlpha / 255)),
        ],
      );
    }
    return RepaintBoundary(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final artwork = _artwork();
        return AvesScaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (artwork != null) Positioned.fill(child: _preview(context, artwork)),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 320,
                child: IgnorePointer(child: _TopScrim()),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const BackButton(color: Colors.white),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _applyPreset(WallpaperEffects.muzeiDefaults),
                          child: Text(
                            l10n.muzeiWallpaperEffectsMuzeiDefaults,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.muzeiWallpaperEffectsResetZero,
                          icon: const Icon(AIcons.restore, color: Colors.white),
                          onPressed: () => _applyPreset(const WallpaperEffects()),
                        ),
                      ],
                    ),
                    TabBar(
                      controller: _tabs,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white60,
                      indicatorColor: Colors.white,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(text: l10n.muzeiWallpaperEffectsHome),
                        Tab(text: l10n.muzeiWallpaperEffectsLock),
                      ],
                    ),
                    SizedBox(
                      height: 2,
                      child: _controller.baking ? const LinearProgressIndicator(minHeight: 2) : null,
                    ),
                    Expanded(
                      // The panel must stay reachable on a short screen without
                      // pushing the tabs off; it only scrolls when it has to.
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _EffectsPanel(
                          effects: _currentEffects,
                          link: _effects.link,
                          onChanged: _update,
                          onLinkChanged: _setLink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

class _EffectsPanel extends StatelessWidget {
  final WallpaperEffects effects;
  final bool link;
  final ValueChanged<WallpaperEffects> onChanged;
  final ValueChanged<bool> onLinkChanged;

  const new({
    required this.effects,
    required this.link,
    required this.onChanged,
    required this.onLinkChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .42),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EffectSlider(
            label: l10n.muzeiWallpaperEffectsBlur,
            value: effects.blur.toDouble(),
            max: WallpaperEffects.maxBlur.toDouble(),
            onChanged: (value) => onChanged(effects.copyWith(blur: value.round())),
          ),
          _EffectSlider(
            label: l10n.muzeiWallpaperEffectsDim,
            value: effects.dim.toDouble(),
            max: WallpaperEffects.maxDim.toDouble(),
            onChanged: (value) => onChanged(effects.copyWith(dim: value.round())),
          ),
          _EffectSlider(
            label: l10n.muzeiWallpaperEffectsGrey,
            value: effects.grey.toDouble(),
            max: WallpaperEffects.maxGrey.toDouble(),
            onChanged: (value) => onChanged(effects.copyWith(grey: value.round())),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.muzeiWallpaperEffectsLink,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ),
              Switch(
                value: link,
                onChanged: onLinkChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.white38,
                inactiveThumbColor: Colors.white54,
                inactiveTrackColor: Colors.white12,
              ),
            ],
          ),
        ],
      ),
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
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
              ),
              Text(
                value.round().toString(),
                style: textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              valueIndicatorColor: Colors.white,
              valueIndicatorTextStyle: const TextStyle(color: Colors.black),
            ),
            child: Slider(
              value: value,
              max: max,
              divisions: max.round(),
              label: value.round().toString(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopScrim extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: .55), Colors.transparent],
        ),
      ),
    );
  }
}
