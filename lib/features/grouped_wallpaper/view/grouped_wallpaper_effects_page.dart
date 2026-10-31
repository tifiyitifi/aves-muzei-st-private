import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_auto_advance_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_effects_sync_page.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Edits the home and lock effects of one wallpaper group, with a live preview.
///
/// Modelled on Muzei's effects screen, but bound to the group being viewed: each
/// group owns its effects, so a private group can be blurred while a public one
/// stays sharp. The preview applies the very same math on the GPU, which is
/// instant, while the debounced save re-bakes the real wallpaper.
///
/// Effects are applied immediately rather than through the page's range draft:
/// they are display preferences, and the live wallpaper should follow the
/// sliders without a separate "save" step.
class GroupedWallpaperEffectsPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups/effects';

  final String groupId;
  final WallpaperGroupRangeController controller;

  const new({
    super.key,
    required this.groupId,
    required this.controller,
  });

  @override
  State<GroupedWallpaperEffectsPage> createState() => _GroupedWallpaperEffectsPageState();
}

class _GroupedWallpaperEffectsPageState extends State<GroupedWallpaperEffectsPage> with SingleTickerProviderStateMixin {
  /// Keeps a slider drag from rebaking the wallpaper on every pixel step.
  static const _applyDelay = Duration(milliseconds: 300);

  late final TabController _tabs;
  late WallpaperEffectsConfig _effects;
  Timer? _timer;
  bool _dirty = false;

  GroupedWallpaperState? _state;
  String? _previewPath;

  WallpaperGroupRangeController get _controller => widget.controller;

  bool get _editingLock => _tabs.index == 1;

  /// The values on screen: the surface being edited, honouring the link toggle.
  WallpaperEffects get _currentEffects => _editingLock ? _effects.effectiveLock : _effects.home;

  @override
  void initState() {
    super.initState();
    _effects = _controller.effectsOf(widget.groupId);
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    unawaited(_loadPreview());
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

  Future<void> _loadPreview() async {
    final state = await wallpaperEngineLink.readState();
    // Only the group currently on the wallpaper has a baked preview; another
    // group's effects still save and apply when it plays next.
    final path = state?.groupId == widget.groupId ? await wallpaperEngineLink.currentPhotoPath() : null;
    if (!mounted) return;
    setState(() {
      _state = state;
      _previewPath = path;
    });
  }

  void _update(WallpaperEffects value) {
    setState(() {
      _effects = _effects.applyTo(onLock: _editingLock, value: value);
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
    unawaited(_save());
  }

  Future<void> _save() async {
    await _controller.setEffects(widget.groupId, _effects);
    // The next frame uses the new effects; the engine skips the bake when the
    // group is not the current one, so this is cheap for other groups.
    await wallpaperEngineLink.prepare();
  }

  /// Applies a preset to the edited surface and saves it right away: presets are
  /// deliberate choices, not slider drags, so there is nothing to debounce.
  void _applyPreset(WallpaperEffects preset) {
    setState(() {
      _effects = _effects.applyTo(onLock: _editingLock, value: preset);
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

  /// Turns the home scroll effect on or off for this group.
  ///
  /// It is a layout change, so the save re-bakes the frame on screen: the very
  /// next look at the home screen shows the wider photo instead of waiting for
  /// another one.
  void _setHomeScrollEffect(bool enabled) {
    setState(() {
      _effects = _effects.copyWith(homeScrollEffect: enabled);
      _dirty = true;
    });
    _apply();
  }

  /// Opens the group's auto-advance editor.
  ///
  /// The interval and the ordering stay group-level and shared by both surfaces,
  /// so this is one row instead of a per-tab switch.
  Future<void> _openAutoAdvance(WallpaperGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperAutoAdvancePage.routeName),
        builder: (_) => GroupedWallpaperAutoAdvancePage(
          groupId: group.id,
          controller: _controller.groupController,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// The settings that belong to the wallpaper rather than to one surface.
  ///
  /// The scroll switch is offered on the home tab only: the lock screen centers
  /// its frame instead of panning, so a lock switch would record a value nothing
  /// draws. Auto-advance is shared, so its row is shown on both tabs.
  Widget _settingsPanel(BuildContext context, WallpaperGroup group) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .42),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_editingLock)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.wallpaperUseScrollEffect,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Switch(
                    value: _effects.homeScrollEffect,
                    onChanged: _setHomeScrollEffect,
                  ),
                ],
              ),
            ),
          ListTile(
            title: Text(l10n.muzeiWallpaperAutoAdvance, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              groupedWallpaperAutoAdvanceSummary(context, group),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(AIcons.next, color: Colors.white70),
            onTap: () => unawaited(_openAutoAdvance(group)),
          ),
        ],
      ),
    );
  }

  Future<void> _openSync() async {
    _apply();
    final copied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperEffectsSyncPage.routeName),
        builder: (_) => GroupedWallpaperEffectsSyncPage(
          sourceGroupId: widget.groupId,
          effects: _effects,
          controller: _controller,
        ),
      ),
    );
    if (!mounted || copied != true) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.groupedWallpaperEffectsSyncDone)));
  }

  Widget? _artwork() {
    final path = _previewPath;
    if (path == null) return null;
    return Image.file(
      File(path),
      key: ValueKey('grouped-effects-preview-$path'),
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }

  /// Applies the effects to the preview on the GPU.
  ///
  /// Same math as the baker, so what the sliders show is what the next bake
  /// writes: the sigma is relative to the display height and the dim uses the
  /// baked frame's own darkness.
  Widget _preview(BuildContext context, Widget artwork) {
    final effects = _currentEffects;
    final darkness = _state?.currentSlot?.darkness ?? .5;
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
    final group = _controller.groups.firstWhereOrNull((candidate) => candidate.id == widget.groupId);
    final groupName = group == null ? '' : wallpaperGroupName(context, group);
    final canSync = _controller.groups.any((candidate) => candidate.id != widget.groupId);
    final artwork = _artwork();
    return AvesScaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (artwork != null)
            Positioned.fill(child: _preview(context, artwork))
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (groupName.isNotEmpty)
                      Text(
                        groupName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.groupedWallpaperEffectsNoPreview,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
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
                    Expanded(
                      child: Text(
                        l10n.muzeiWallpaperEffects,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.groupedWallpaperEffectsSync,
                      icon: const Icon(AIcons.copy, color: Colors.white),
                      onPressed: canSync ? () => unawaited(_openSync()) : null,
                    ),
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
                const SizedBox(height: 2),
                if (group != null) _settingsPanel(context, group),
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
