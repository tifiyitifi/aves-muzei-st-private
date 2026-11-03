import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_capability.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_auto_advance_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_effects_sync_page.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
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

  /// The group aggregate the editor reads and writes.
  ///
  /// It never needed the page's range draft: effects are preferences that are
  /// written straight through (`setEffects`), so binding to the aggregate lets
  /// the immersive view open the same editor without owning a draft.
  final WallpaperGroupController controller;

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

  /// The surface the preview was last loaded for, so the tab animation does not
  /// trigger a platform probe on every tick.
  int _previewTabIndex = 0;

  GroupedWallpaperState? _state;
  String? _previewPath;

  /// Whether the preview source is a sharp frame the GPU may filter.
  ///
  /// A split group's decoy is one file with the lock effects already baked in, so
  /// filtering it again would apply them twice; it is shown as-is instead.
  bool _previewAppliesEffects = true;

  /// A framing edit changes the baked pixels, unlike the effect sliders, so the
  /// next save has to re-read the (key-derived) preview path.
  bool _framingDirty = false;

  /// Whether this device can pan the wallpaper at all, for the switch's note.
  WallpaperCapability _capability = WallpaperCapability.unknown;

  WallpaperGroupController get _controller => widget.controller;

  bool get _editingLock => _tabs.index == 1;

  bool get _panUnsupported => _capability.panVerdict == CapabilityVerdict.unsupported;

  /// The home frame is baked wide, so its rotation and fit are not applied.
  ///
  /// The engine resolves the *effective* scroll effect the same way: the user's
  /// switch alone is not enough while the launcher never pans.
  bool get _homeFrameIsWide => _effects.homeScrollEffect && _capability.bakesWide;

  /// Whether the framing controls may be edited on the surface being shown.
  ///
  /// The lock screen never pans, so its framing always applies.
  bool get _framingEditable => _editingLock || !_homeFrameIsWide;

  /// The values on screen: the surface being edited, honouring the link toggle.
  WallpaperEffects get _currentEffects => _editingLock ? _effects.effectiveLock : _effects.home;

  /// The framing of the surface being edited.
  ///
  /// The link deliberately does not cover framing: each surface judges its own
  /// orientation against its own screen.
  WallpaperFraming get _currentFraming => _editingLock ? _effects.framingLock : _effects.framingHome;

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

  void _onTabChanged() {
    setState(() {});
    // Each surface may draw another photo (the decoy is not the home queue), so
    // the preview has to follow the tab. The controller also notifies during the
    // animation; only an actual surface change needs a reload.
    if (_tabs.index == _previewTabIndex) return;
    _previewTabIndex = _tabs.index;
    unawaited(_loadPreview());
  }

  /// Reads the framing/effects preview source of the surface being edited.
  ///
  /// The baked frame of that surface is used, not the original entry: it already
  /// has the geometry (rotation and fit) applied, so the preview shows what the
  /// wallpaper really draws, random direction included. The home file is the
  /// sharp base, so its effects are still applied on the GPU; the lock file is
  /// final and shown as-is.
  Future<void> _loadPreview() async {
    final state = await wallpaperEngineLink.readState();
    final capability = await wallpaperEngineLink.capability();
    // Only the group currently on the wallpaper has a baked preview; another
    // group's effects still save and apply when it plays next.
    final preview = state?.groupId == widget.groupId ? await _previewOfSurface() : (path: null, appliesEffects: true);
    if (!mounted) return;
    setState(() {
      _state = state;
      _capability = capability;
      _previewPath = preview.path;
      _previewAppliesEffects = preview.appliesEffects;
    });
  }

  /// The preview source and whether its effects are still to be applied.
  Future<({String? path, bool appliesEffects})> _previewOfSurface() async {
    final surface = _editingLock ? WallpaperSurface.lock : WallpaperSurface.home;
    final path = await wallpaperEngineLink.currentPhotoPath(surface: surface);
    // The lock surface's file is already the final lock image (decoy or the home
    // queue's lock image), framing and effects included. Only the home surface
    // hands back a sharp base the GPU may filter live.
    return (path: path, appliesEffects: !surface.isLock);
  }

  /// Re-reads the preview path after a framing edit re-baked the pixels.
  Future<void> _refreshPreviewPath() async {
    if (_state?.groupId != widget.groupId) return;
    final preview = await _previewOfSurface();
    if (!mounted || preview.path == _previewPath) return;
    setState(() {
      _previewPath = preview.path;
      _previewAppliesEffects = preview.appliesEffects;
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
    // A framing edit changes the baked pixels under a new cache key, so the
    // preview has to pick up the new file. The lock preview is the final lock
    // image, so any lock edit needs that too; the home effect sliders keep the
    // same sharp base and stay live on the GPU.
    if (_framingDirty || _editingLock) {
      _framingDirty = false;
      await _refreshPreviewPath();
    }
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

  /// Applies a rotation/fit choice and saves it right away: it is a discrete
  /// choice, not a slider drag, and the wallpaper has to re-bake the pixels.
  void _setFraming(WallpaperFraming value) {
    if (!_framingEditable) return;
    setState(() {
      _effects = _effects.withFraming(onLock: _editingLock, value: value);
      _dirty = true;
      _framingDirty = true;
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
          controller: _controller,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.wallpaperUseScrollEffect,
                          style: const TextStyle(color: Colors.white),
                        ),
                        // Keep the switch usable: the group keeps its own
                        // preference, and a launcher that starts panning later
                        // follows it without the user having to come back.
                        if (_panUnsupported && _effects.homeScrollEffect)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              l10n.wallpaperScrollEffectUnsupported,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                      ],
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
    // A decoy file is already the final lock frame: filtering it again would
    // apply the lock effects twice, so it is shown as-is.
    if (!_previewAppliesEffects) return RepaintBoundary(child: artwork);
    final effects = _currentEffects;
    final darkness = _editingLock ? (_state?.lock?.darkness ?? .5) : (_state?.currentSlot?.darkness ?? .5);
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
                      framing: _currentFraming,
                      framingEditable: _framingEditable,
                      link: _effects.link,
                      onChanged: _update,
                      onFramingChanged: _setFraming,
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
  final WallpaperFraming framing;
  final bool framingEditable;
  final bool link;
  final ValueChanged<WallpaperEffects> onChanged;
  final ValueChanged<WallpaperFraming> onFramingChanged;
  final ValueChanged<bool> onLinkChanged;

  const new({
    required this.effects,
    required this.framing,
    required this.framingEditable,
    required this.link,
    required this.onChanged,
    required this.onFramingChanged,
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
          _FramingSection(
            framing: framing,
            editable: framingEditable,
            onChanged: onFramingChanged,
          ),
          const Divider(color: Colors.white24, height: 24),
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

class _FramingSection extends StatelessWidget {
  final WallpaperFraming framing;
  final bool editable;
  final ValueChanged<WallpaperFraming> onChanged;

  const new({
    required this.framing,
    required this.editable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.groupedWallpaperImageFraming,
            style: textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.groupedWallpaperImageFit,
          style: textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 6),
        SegmentedButton<WallpaperImageFit>(
          segments: [
            ButtonSegment(value: WallpaperImageFit.fill, label: Text(l10n.groupedWallpaperImageFitFill)),
            ButtonSegment(value: WallpaperImageFit.fit, label: Text(l10n.groupedWallpaperImageFitFit)),
            ButtonSegment(value: WallpaperImageFit.stretch, label: Text(l10n.groupedWallpaperImageFitStretch)),
          ],
          selected: {framing.fit},
          showSelectedIcon: false,
          style: _framingButtonStyle(),
          onSelectionChanged: editable ? (selection) => onChanged(framing.copyWith(fit: selection.first)) : null,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.groupedWallpaperRotation,
          style: textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        DropdownButton<WallpaperRotation>(
          value: framing.rotation,
          isExpanded: true,
          dropdownColor: const Color(0xFF2A2A2A),
          iconEnabledColor: Colors.white,
          underline: const SizedBox.shrink(),
          style: textTheme.bodyMedium?.copyWith(color: Colors.white),
          items: [
            DropdownMenuItem(value: WallpaperRotation.off, child: Text(l10n.groupedWallpaperRotationOff, style: const TextStyle(color: Colors.white))),
            DropdownMenuItem(value: WallpaperRotation.clockwise, child: Text(l10n.groupedWallpaperRotationClockwise, style: const TextStyle(color: Colors.white))),
            DropdownMenuItem(value: WallpaperRotation.counterClockwise, child: Text(l10n.groupedWallpaperRotationCounterClockwise, style: const TextStyle(color: Colors.white))),
            DropdownMenuItem(value: WallpaperRotation.random, child: Text(l10n.groupedWallpaperRotationRandom, style: const TextStyle(color: Colors.white))),
          ],
          onChanged: editable
              ? (value) {
                  if (value != null) onChanged(framing.copyWith(rotation: value));
                }
              : null,
        ),
        if (!editable)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              l10n.groupedWallpaperFramingWideNote,
              style: textTheme.bodySmall?.copyWith(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// The segmented control reads on the dark, blurred preview.
ButtonStyle _framingButtonStyle() => SegmentedButton.styleFrom(
  foregroundColor: Colors.white,
  selectedForegroundColor: Colors.black,
  selectedBackgroundColor: Colors.white,
  side: const BorderSide(color: Colors.white24),
  textStyle: const TextStyle(fontSize: 12),
);

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
