import 'dart:async';
import 'dart:typed_data';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_cover.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_display.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_gestures.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller_factory.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_view_page.dart';
import 'package:aves/features/muzei_wallpaper/view/slot_artwork_image.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_overflow_button.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Foreground surface of the Muzei-style live wallpaper.
///
/// Artwork-first like Muzei's main screen: the photo fills the window and one
/// row floats over it (title line, "touch to view", next, overflow). Everything
/// Muzei put in its bottom tabs (sources, effects) moved into the overflow,
/// because this page is reached from the drawer and has a back arrow instead.
///
/// A tap toggles the overlay so the user can look at the picture alone, and a
/// long press opens the immersive artwork view. Panning and pinch-zooming are
/// local to the page — the wallpaper keeps showing the whole frame — and the
/// artwork is laid out at its cover size, so panning works even at 1x and can
/// reach the parts the wallpaper crops away.
class MuzeiWallpaperPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper';

  const new({super.key});

  @override
  State<MuzeiWallpaperPage> createState() => _MuzeiWallpaperPageState();
}

class _MuzeiWallpaperPageState extends State<MuzeiWallpaperPage> with WidgetsBindingObserver {
  late final Future<WallpaperController> _controllerFuture;
  WallpaperController? _controller;

  final TransformationController _viewport = TransformationController();

  bool _panelVisible = true;

  /// Recent-artwork preview, used only while the queue is empty.
  ///
  /// The page bakes it in memory instead of writing a slot: showing history must
  /// never change the wallpaper or the artwork that is queued next.
  AvesEntry? _fallbackEntry;
  Uint8List? _fallbackSharp;
  double? _fallbackAspect;
  bool _fallbackLoading = false;

  String? _singleEntryTitle;

  /// Identity of the geometry the viewport was last centered for.
  ///
  /// Changing artwork or rotating recenters the view, like Muzei resets its
  /// viewport on a new artwork; a rebuild for any other reason must not disturb
  /// the user's pan and zoom.
  (String, Size, Size)? _viewportGeometry;

  /// Pointers currently down, to recognise a three-finger tap.
  final Set<int> _pointers = {};
  int _maxPointers = 0;
  Offset? _pointerOrigin;
  bool _pointerMoved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controllerFuture = _createController();
  }

  Future<WallpaperController> _createController() async {
    final controller = await WallpaperControllerFactory.create();
    if (!mounted) {
      controller.dispose();
      throw StateError('the wallpaper page was closed while loading');
    }
    // A wallpaper tap promotes the prefetched slot natively. Adopt it and refill
    // the freed slot right away instead of waiting for the app to resume.
    WallpaperBridge.instance.setRequestHandler(
      onAdvanceRequested: () => unawaited(controller.syncRuntime()),
    );
    unawaited(_loadSingleEntryTitle(controller));
    unawaited(_loadFallback(controller));
    return controller;
  }

  Future<void> _loadSingleEntryTitle(WallpaperController controller) async {
    final id = controller.prefs.scope.singleEntryId;
    if (id == null) return;
    final entry = await controller.loadEntry(id);
    if (!mounted || controller.prefs.scope.singleEntryId != id) return;
    setState(() => _singleEntryTitle = entry?.bestTitle);
  }

  /// Prepares the "last artwork that still exists" preview.
  ///
  /// Runs when the queue is empty, which is the case this page used to answer
  /// with a black screen.
  Future<void> _loadFallback(WallpaperController controller) async {
    // Only an empty queue needs a preview; otherwise the page shows the bake.
    if (controller.current != null || _fallbackLoading || _fallbackEntry != null) return;
    _fallbackLoading = true;
    try {
      final entry = await controller.loadFallbackEntry();
      if (!mounted || entry == null) return;
      final bake = await controller.bakePreview(entry);
      if (!mounted || bake == null) return;
      setState(() {
        _fallbackEntry = entry;
        _fallbackSharp = bake.sharpPng;
        _fallbackAspect = bake.size.height > 0 ? bake.size.width / bake.size.height : null;
      });
    } finally {
      _fallbackLoading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.syncRuntime());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WallpaperBridge.instance.setRequestHandler();
    _viewport.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// The artwork the page is showing, or null while there is nothing to show.
  ///
  /// The sharp bake is deliberate: Muzei's main screen previews the artwork, and
  /// the wallpaper effects are what the wallpaper itself applies. Showing the
  /// effect image here would hide the photo behind the very blur the user is
  /// trying to look at.
  Widget? _artwork(WallpaperController controller) {
    final slot = controller.current;
    final file = controller.currentFile;
    if (slot != null && file != null) {
      return Image(
        // Slot files are reused for different artworks, so the widget and the
        // cache key both follow the artwork, not just the path.
        image: SlotArtworkImage(file: file, contentKey: slot.artwork.entryId),
        key: ValueKey('${slot.id}-${slot.artwork.entryId}'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    final image = _fallbackSharp;
    if (image != null) {
      return Image.memory(
        image,
        key: ValueKey('fallback-${_fallbackEntry?.id}'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return null;
  }

  /// The entry behind the current artwork, for the viewer and "open with".
  Future<AvesEntry?> _currentEntry(WallpaperController controller) async {
    final entry = await controller.loadCurrentEntry();
    return entry ?? _fallbackEntry;
  }

  Future<void> _openArtwork(WallpaperController controller) async {
    final entry = await _currentEntry(controller);
    if (!mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.muzeiWallpaperMissing)),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: EntryViewerPage.routeName),
        builder: (_) => EntryViewerPage(initialEntry: entry),
      ),
    );
  }

  /// Long press on "touch to view": hand the artwork to another app.
  Future<void> _openWith(WallpaperController controller) async {
    final entry = await _currentEntry(controller);
    if (!mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.muzeiWallpaperMissing)),
      );
      return;
    }
    final opened = await appService.open(entry.uri, entry.mimeTypeAnySubtype, forceChooser: true);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.noMatchingAppDialogMessage)),
    );
  }

  void _runGesture(WallpaperController controller, WallpaperTapAction action) {
    switch (action) {
      case WallpaperTapAction.temporaryDisable:
        // The page already shows the unprocessed artwork, so there is nothing to
        // reveal here; the binding still applies to the wallpaper itself.
        break;
      case WallpaperTapAction.nextArtwork:
        unawaited(controller.advance());
      case WallpaperTapAction.viewArtwork:
        unawaited(_openArtwork(controller));
      case WallpaperTapAction.none:
        break;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _pointerOrigin = event.position;
      _pointerMoved = false;
      _maxPointers = 0;
    }
    _pointers.add(event.pointer);
    if (_pointers.length > _maxPointers) _maxPointers = _pointers.length;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _pointerOrigin;
    if (origin != null && (event.position - origin).distance > kTouchSlop * 2) {
      _pointerMoved = true;
    }
  }

  void _onPointerUp(PointerEvent event, WallpaperController controller) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;
    final fingers = _maxPointers;
    final moved = _pointerMoved;
    _maxPointers = 0;
    _pointerOrigin = null;
    _pointerMoved = false;
    if (fingers >= 3 && !moved) {
      _runGesture(controller, controller.prefs.gestures.threeFinger);
    }
  }

  void _togglePanel() {
    setState(() => _panelVisible = !_panelVisible);
  }

  /// Opens the immersive artwork view — Muzei's artwork screen without its UI.
  ///
  /// A separate route keeps this page's gestures simple: the view page owns its
  /// pan/zoom bounds and hides the system bars for as long as it is open.
  Future<void> _openViewPage(WallpaperController controller) async {
    final artwork = _artwork(controller);
    if (artwork == null) return;
    final title = _titleText(context, controller);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: MuzeiWallpaperViewPage.routeName),
        builder: (_) => MuzeiWallpaperViewPage(
          artwork: artwork,
          aspectRatio: _artworkAspect(controller),
          title: title,
        ),
      ),
    );
  }

  /// Aspect ratio of the artwork on screen, when the bake recorded it.
  double? _artworkAspect(WallpaperController controller) {
    return controller.current?.artwork.aspectRatio ?? _fallbackAspect;
  }

  /// Centers the artwork until the user pans, and recenters whenever the
  /// artwork or the window changes.
  ///
  /// The artwork is laid out at its cover size, so a rebuild for an unrelated
  /// reason must not throw away the user's pan and zoom; only a new artwork or a
  /// new window size does, like Muzei resetting its viewport.
  void _syncViewport(String contentKey, Size childSize, Size viewportSize) {
    final geometry = (contentKey, childSize, viewportSize);
    if (_viewportGeometry == geometry) return;
    _viewportGeometry = geometry;
    // The controller notifies its viewer, so it must not change during build.
    final matrix = centeredCoverMatrix(childSize, viewportSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewport.value = matrix;
    });
  }

  String? _titleText(BuildContext context, WallpaperController controller) {
    if (controller.prefs.titleMode == WallpaperTitleMode.fileName) {
      return controller.current?.artwork.title ?? _fallbackEntry?.bestTitle;
    }
    return _sourceName(context, controller);
  }

  /// The source in the user's words: what Muzei labels the artwork with.
  String _sourceName(BuildContext context, WallpaperController controller) {
    final l10n = context.l10n;
    final scope = controller.prefs.scope;
    switch (scope.kind) {
      case WallpaperSourceKind.single:
        return _singleEntryTitle ?? l10n.muzeiWallpaperSourcesSingle;
      case WallpaperSourceKind.myPhotos:
        if (scope.filters.isEmpty) return l10n.muzeiWallpaperSourcesAllPhotos;
        final labels = scope.filters.map((filter) => filter.getLabel(context)).toList()..sort();
        return labels.length == 1 ? labels.first : l10n.muzeiWallpaperSourceMoreFilters(labels.first, labels.length - 1);
    }
  }

  static String? _statusText(BuildContext context, WallpaperSourceResolution? resolution) {
    final l10n = context.l10n;
    switch (resolution?.status) {
      case WallpaperSourceStatus.empty:
        return l10n.muzeiWallpaperEmpty;
      case WallpaperSourceStatus.unsupported:
        return l10n.muzeiWallpaperUnsupported;
      case WallpaperSourceStatus.missing:
        return l10n.muzeiWallpaperMissing;
      case WallpaperSourceStatus.ready:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AvesScaffold(
      body: FutureBuilder<WallpaperController>(
        future: _controllerFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(message: snapshot.error.toString());
          }
          final controller = snapshot.data;
          if (controller == null) {
            return const _LoadingView();
          }
          _controller ??= controller;
          // The title mode lives in the prefs, not in the controller, and it
          // changes from the overflow menu, so listen to both.
          return ListenableBuilder(
            listenable: Listenable.merge([controller, controller.prefs]),
            builder: (context, _) => _buildContent(context, controller),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, WallpaperController controller) {
    final l10n = context.l10n;
    final artwork = _artwork(controller);
    final status = _statusText(context, controller.resolution);
    final title = _titleText(context, controller);
    final slot = controller.current;
    final contentKey = slot != null ? 'slot-${slot.id}-${slot.artwork.entryId}' : 'fallback-${_fallbackEntry?.id}';

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (artwork != null)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportSize = constraints.biggest;
                final childSize = coverSizeFor(viewportSize, _artworkAspect(controller));
                _syncViewport(contentKey, childSize, viewportSize);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePanel,
                  onLongPress: () => unawaited(_openViewPage(controller)),
                  onDoubleTap: () => _runGesture(controller, controller.prefs.gestures.doubleTap),
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: (event) => _onPointerUp(event, controller),
                    onPointerCancel: (event) => _onPointerUp(event, controller),
                    child: InteractiveViewer(
                      transformationController: _viewport,
                      minScale: WallpaperPrefs.minViewportZoom,
                      maxScale: WallpaperPrefs.maxViewportZoom,
                      // The artwork is laid out at its cover size, larger than the
                      // window, so panning can reach what the wallpaper crops away.
                      constrained: false,
                      child: SizedBox(
                        width: childSize.width,
                        height: childSize.height,
                        child: artwork,
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                controller.error ?? status ?? l10n.muzeiWallpaperEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
              ),
            ),
          ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 180,
          child: IgnorePointer(child: _TopScrim()),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _PanelVisibility(
            visible: _panelVisible,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Navigator.canPop(context) ? const BackButton(color: Colors.white) : const SizedBox(width: 48, height: 48),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _PanelVisibility(
            visible: _panelVisible,
            child: _BottomPanel(
              controller: controller,
              title: title,
              status: status,
              onViewArtwork: () => unawaited(_openArtwork(controller)),
              onOpenWith: () => unawaited(_openWith(controller)),
              aboutBackdrop: () => _artwork(controller) ?? const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades the overlay out and stops it from eating taps while hidden.
class _PanelVisibility extends StatelessWidget {
  final bool visible;
  final Widget child;

  const new({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// The single floating row: title line, "touch to view", next and overflow.
class _BottomPanel extends StatelessWidget {
  final WallpaperController controller;
  final String? title;
  final String? status;
  final VoidCallback onViewArtwork;
  final VoidCallback onOpenWith;
  final Widget Function() aboutBackdrop;

  const new({
    required this.controller,
    required this.title,
    required this.status,
    required this.onViewArtwork,
    required this.onOpenWith,
    required this.aboutBackdrop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final titleText = title;
    final statusText = status;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: .88)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (titleText != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        // The title carries the same actions as "touch to view":
                        // it is the line users point at when they want to see
                        // the artwork, so both must behave alike.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onViewArtwork,
                          onLongPress: onOpenWith,
                          child: Text(
                            titleText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    if (statusText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 16),
                        child: Text(
                          statusText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ),
                    // Long press only fires on this line: the rest of the screen
                    // toggles the overlay instead.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onViewArtwork,
                      onLongPress: onOpenWith,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 10, 24, 10),
                        child: Text(
                          l10n.muzeiWallpaperTouchToView,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.muzeiWallpaperNextAction,
                color: Colors.white,
                onPressed: controller.busy || controller.resolution?.status == WallpaperSourceStatus.empty
                    ? null
                    : controller.advance,
                icon: controller.busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AIcons.next),
              ),
              WallpaperOverflowButton(
                controller: controller,
                section: WallpaperSection.artwork,
                color: Colors.white,
                aboutBackdrop: aboutBackdrop,
              ),
            ],
          ),
        ),
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
          colors: [Colors.black.withValues(alpha: .45), Colors.transparent],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        const Center(child: CircularProgressIndicator()),
        SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (Navigator.canPop(context)) const BackButton(color: Colors.white),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const new({required this.message});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AIcons.info, size: 40, color: Colors.white70),
                const SizedBox(height: 12),
                Text(
                  context.l10n.muzeiWallpaperErrorTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.muzeiWallpaperLoadError(message),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (Navigator.canPop(context)) const BackButton(color: Colors.white),
            ],
          ),
        ),
      ],
    );
  }
}
