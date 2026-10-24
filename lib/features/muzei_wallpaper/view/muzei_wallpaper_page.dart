import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller_factory.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_effects_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_gestures_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_sources_page.dart';
import 'package:aves/features/muzei_wallpaper/view/slot_artwork_image.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Foreground surface of the Muzei-style live wallpaper.
///
/// Artwork-first like Muzei's main screen: the photo fills the window, the
/// controls float over a bottom scrim, and the source/effect editors are opened
/// from the overflow instead of competing with the artwork.
///
/// This is milestone 5 of the port, so the source/effect/gesture editors still
/// live in the controller and arrive as separate pages. The visible attribution
/// is deliberate: the behaviour and visual language are ported from Muzei.
class MuzeiWallpaperPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper';

  const new({super.key});

  @override
  State<MuzeiWallpaperPage> createState() => _MuzeiWallpaperPageState();
}

enum _WallpaperMenuAction {
  sources,
  effects,
  gestures,
  autoAdvance,
  openArtwork,
  setWallpaper,
  refreshStatus,
  syncRuntime,
  debugInfo,
}

class _MuzeiWallpaperPageState extends State<MuzeiWallpaperPage> with WidgetsBindingObserver {
  late final Future<WallpaperController> _controllerFuture;
  WallpaperController? _controller;

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
    return controller;
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
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openArtwork(BuildContext context) async {
    final entry = await _controller?.loadCurrentEntry();
    if (!context.mounted) return;
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

  Future<void> _openSources(BuildContext context, WallpaperController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: MuzeiWallpaperSourcesPage.routeName),
        builder: (_) => MuzeiWallpaperSourcesPage(controller: controller),
      ),
    );
  }

  Future<void> _openEffects(BuildContext context, WallpaperController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: MuzeiWallpaperEffectsPage.routeName),
        builder: (_) => MuzeiWallpaperEffectsPage(controller: controller),
      ),
    );
  }

  Future<void> _openGestures(BuildContext context, WallpaperController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: MuzeiWallpaperGesturesPage.routeName),
        builder: (_) => MuzeiWallpaperGesturesPage(controller: controller),
      ),
    );
  }

  /// Auto-advance is scheduled by the native worker, so it keeps running when
  /// the page is closed; this dialog only chooses the interval.
  Future<void> _showAutoAdvance(BuildContext context, WallpaperController controller) {
    final selected = controller.prefs.autoAdvance.interval;
    return showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.muzeiWallpaperAutoAdvance),
        children: [
          for (final interval in WallpaperInterval.values)
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(
                  controller.setAutoAdvance(controller.prefs.autoAdvance.copyWith(interval: interval)),
                );
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: interval == selected ? const Icon(AIcons.checked, size: 20) : null,
                  ),
                  Expanded(child: Text(_intervalLabel(context, interval))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _intervalLabel(BuildContext context, WallpaperInterval interval) {
    final l10n = context.l10n;
    return switch (interval) {
      WallpaperInterval.m15 => l10n.muzeiWallpaperAutoAdvanceMinutes(15),
      WallpaperInterval.m30 => l10n.muzeiWallpaperAutoAdvanceMinutes(30),
      WallpaperInterval.h1 => l10n.muzeiWallpaperAutoAdvanceHours(1),
      WallpaperInterval.h3 => l10n.muzeiWallpaperAutoAdvanceHours(3),
      WallpaperInterval.h6 => l10n.muzeiWallpaperAutoAdvanceHours(6),
      WallpaperInterval.h24 => l10n.muzeiWallpaperAutoAdvanceDays(1),
      WallpaperInterval.h72 => l10n.muzeiWallpaperAutoAdvanceDays(3),
      WallpaperInterval.never => l10n.muzeiWallpaperAutoAdvanceOff,
    };
  }

  Future<void> _openChooser(BuildContext context, WallpaperController controller) async {
    final opened = await controller.openChooser();
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.muzeiWallpaperChooserUnavailable)),
    );
  }

  Future<void> _showDebugInfo(BuildContext context, WallpaperController controller) {
    final state = controller.state;
    final current = controller.current;
    final next = controller.next;
    final next2 = controller.next2;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.muzeiWallpaperDebugInfo),
        content: SelectableText(
          'generation ${state.generation}\n'
          'current slot ${state.current} · entry ${current?.artwork.entryId ?? '-'}\n'
          'next slot ${state.next} · entry ${next?.artwork.entryId ?? '-'}\n'
          'next2 slot ${state.next2} · entry ${next2?.artwork.entryId ?? '-'}\n'
          'source ${controller.resolution?.status.name ?? '-'} · total ${controller.resolution?.total ?? 0}\n'
          'service ${controller.serviceActive ? 'active' : 'inactive'}\n'
          'state ${state.sourceRevision}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(_WallpaperMenuAction action, WallpaperController controller) async {
    switch (action) {
      case _WallpaperMenuAction.sources:
        await _openSources(context, controller);
      case _WallpaperMenuAction.effects:
        await _openEffects(context, controller);
      case _WallpaperMenuAction.gestures:
        await _openGestures(context, controller);
      case _WallpaperMenuAction.autoAdvance:
        await _showAutoAdvance(context, controller);
      case _WallpaperMenuAction.openArtwork:
        await _openArtwork(context);
      case _WallpaperMenuAction.setWallpaper:
        await _openChooser(context, controller);
      case _WallpaperMenuAction.refreshStatus:
        await controller.refreshServiceActive();
      case _WallpaperMenuAction.syncRuntime:
        await controller.syncRuntime();
      case _WallpaperMenuAction.debugInfo:
        await _showDebugInfo(context, controller);
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
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _buildContent(context, controller),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, WallpaperController controller) {
    final l10n = context.l10n;
    final current = controller.current;
    final file = controller.currentFile;
    final status = _statusText(context, controller.resolution);
    final error = controller.error;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (file != null && current != null)
          Image(
            // The preview must decode the artwork currently in the slot, not
            // the first artwork the slot ever held; see [SlotArtworkImage].
            image: SlotArtworkImage(file: file, contentKey: current.artwork.entryId),
            key: ValueKey('${current.id}-${current.artwork.entryId}'),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const SizedBox(),
          ),
        if (file == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error ?? status ?? l10n.muzeiWallpaperEmpty,
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
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomInfo(
            controller: controller,
            status: status,
            onOpenArtwork: () => _openArtwork(context),
            onOpenChooser: () => _openChooser(context, controller),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                if (Navigator.canPop(context))
                  const BackButton(color: Colors.white)
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    l10n.muzeiWallpaperPageTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                ),
                PopupMenuButton<_WallpaperMenuAction>(
                  icon: const Icon(AIcons.more, color: Colors.white),
                  tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  onSelected: (action) => _onMenu(action, controller),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _WallpaperMenuAction.sources,
                      child: Text(l10n.muzeiWallpaperSources),
                    ),
                    PopupMenuItem(
                      value: _WallpaperMenuAction.effects,
                      child: Text(l10n.muzeiWallpaperEffects),
                    ),
                    PopupMenuItem(
                      value: _WallpaperMenuAction.gestures,
                      child: Text(l10n.muzeiWallpaperGestures),
                    ),
                    PopupMenuItem(
                      value: _WallpaperMenuAction.autoAdvance,
                      child: Text(l10n.muzeiWallpaperAutoAdvance),
                    ),
                    PopupMenuItem(
                      value: _WallpaperMenuAction.openArtwork,
                      child: Text(l10n.muzeiWallpaperOpenArtwork),
                    ),
                    PopupMenuItem(
                      value: _WallpaperMenuAction.setWallpaper,
                      child: Text(l10n.muzeiWallpaperSetAction),
                    ),
                    PopupMenuItem(
                      value: _WallpaperMenuAction.refreshStatus,
                      child: Text(l10n.muzeiWallpaperRefreshStatus),
                    ),
                    if (kDebugMode) ...[
                      PopupMenuItem(
                        value: _WallpaperMenuAction.syncRuntime,
                        child: Text(l10n.muzeiWallpaperSyncRuntime),
                      ),
                      PopupMenuItem(
                        value: _WallpaperMenuAction.debugInfo,
                        child: Text(l10n.muzeiWallpaperDebugInfo),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
}

class _BottomInfo extends StatelessWidget {
  final WallpaperController controller;
  final String? status;
  final VoidCallback onOpenArtwork;
  final VoidCallback onOpenChooser;

  const new({
    required this.controller,
    required this.status,
    required this.onOpenArtwork,
    required this.onOpenChooser,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = controller.current;
    final statusText = status;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: .92)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (current != null)
                InkWell(
                  onTap: onOpenArtwork,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.artwork.title ?? l10n.muzeiWallpaperPageTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (current.artwork.byline != null)
                          Text(
                            current.artwork.byline!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(AIcons.info, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.muzeiWallpaperAttribution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                  ),
                ],
              ),
              if (statusText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: controller.busy ? null : onOpenChooser,
                      icon: const Icon(AIcons.setAs),
                      label: Text(
                        controller.serviceActive ? l10n.muzeiWallpaperActive : l10n.muzeiWallpaperSetAction,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: l10n.muzeiWallpaperNextAction,
                    onPressed: controller.busy || controller.resolution?.status == WallpaperSourceStatus.empty
                        ? null
                        : controller.advance,
                    icon: controller.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AIcons.next),
                  ),
                ],
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
          colors: [Colors.black.withValues(alpha: .55), Colors.transparent],
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
