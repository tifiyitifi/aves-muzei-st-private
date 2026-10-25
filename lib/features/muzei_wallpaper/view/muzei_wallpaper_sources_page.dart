import 'dart:async';

import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_single_artwork_store.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_source_reset_dialog.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_host_page.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_session.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_overflow_button.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/filter_bar.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Edits the wallpaper source.
///
/// Mirrors Muzei's Sources screen: a local source is either the user's photos
/// (a collection filter) or a single artwork. A change is applied immediately,
/// exactly like Muzei, because the wallpaper is the user's only preview.
///
/// The page edits the live [WallpaperController] instead of creating a second
/// one: `state.json` has a single Dart writer.
class MuzeiWallpaperSourcesPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/sources';

  final WallpaperController controller;

  const new({
    super.key,
    required this.controller,
  });

  @override
  State<MuzeiWallpaperSourcesPage> createState() => _MuzeiWallpaperSourcesPageState();
}

class _MuzeiWallpaperSourcesPageState extends State<MuzeiWallpaperSourcesPage> {
  late WallpaperSourceScope _scope;
  AvesEntry? _singleEntry;
  bool _applying = false;

  /// Guards a source picker while its data preloads, before the route exists.
  bool _pickingSource = false;

  /// True while the chosen artwork is being copied next to the wallpaper.
  bool _copying = false;

  WallpaperController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scope = _controller.prefs.scope;
    unawaited(_loadSingleEntry());
  }

  Future<void> _loadSingleEntry() async {
    final id = _scope.singleEntryId;
    if (id == null) return;
    final entry = await _controller.loadEntry(id);
    if (!mounted || _scope.singleEntryId != id) return;
    setState(() => _singleEntry = entry);
  }

  Future<void> _selectKind(WallpaperSourceKind? kind) async {
    if (kind == null || kind == _scope.kind) return;
    if (_applying || _controller.busy) return;
    if (kind == WallpaperSourceKind.single) {
      // The copy outlives source changes, so an artwork already chosen comes
      // back as it was — even when its original photo was deleted meanwhile.
      // Only a source that was never configured needs a pick.
      final configured = _scope.singleArtwork != null || (_scope.singleEntryId ?? 0) > 0;
      if (configured) {
        await _apply(_scope.copyWith(kind: kind));
        unawaited(_loadSingleEntry());
        return;
      }
      // Choosing the single source means choosing an artwork; do not leave the
      // wallpaper pointing at an unconfigured or uncopied source.
      await _pickSingle();
      return;
    }
    await _apply(_scope.copyWith(kind: kind));
  }

  /// Opens the shared media-set picker and applies the returned filters.
  Future<void> _pickSource() async {
    if (_pickingSource || _applying || _controller.busy) return;
    _pickingSource = true;
    try {
      final source = context.read<CollectionSource>();
      final result = await Navigator.of(context).push<WallpaperSourcePickResult>(
        MaterialPageRoute(
          settings: const RouteSettings(name: WallpaperSourcePickHostPage.routeName),
          builder: (_) => WallpaperSourcePickHostPage(
            source: source,
            mode: WallpaperSourcePickMode.filters,
            initialFilters: _scope.kind == WallpaperSourceKind.myPhotos ? _scope.filters : const {},
          ),
        ),
      );
      if (result is! WallpaperSourcePickFiltersResult || !mounted) return;
      await _apply(
        _scope.copyWith(
          kind: WallpaperSourceKind.myPhotos,
          filters: result.filters,
        ),
      );
    } finally {
      _pickingSource = false;
    }
  }

  /// Return to "all photos": the same result as removing the source chip, offered
  /// as an explicit action because the chip is easy to miss.
  ///
  /// The single artwork's copy is not touched: switching back to it later must
  /// still work even if its original photo is gone.
  Future<void> _clearSource() => _apply(
    _scope.copyWith(
      kind: WallpaperSourceKind.myPhotos,
      filters: const {},
    ),
  );

  /// Resets the photo source, asking first unless the user opted out.
  Future<void> _confirmClearSource() async {
    if (_applying || _controller.busy) return;
    final confirmed = await confirmWallpaperSourceReset(context);
    if (!confirmed || !mounted) return;
    await _clearSource();
  }

  /// Opens the shared media-set picker and copies the picked artwork.
  Future<void> _pickSingle() async {
    if (_pickingSource || _applying || _controller.busy) return;
    _pickingSource = true;
    try {
      final source = context.read<CollectionSource>();
      final result = await Navigator.of(context).push<WallpaperSourcePickResult>(
        MaterialPageRoute(
          settings: const RouteSettings(name: WallpaperSourcePickHostPage.routeName),
          builder: (_) => WallpaperSourcePickHostPage(
            source: source,
            mode: WallpaperSourcePickMode.single,
            initialFilters: _scope.kind == WallpaperSourceKind.myPhotos ? _scope.filters : const {},
          ),
        ),
      );
      if (result is! WallpaperSourcePickEntryResult || !mounted) return;
      await _copyAndApply(result.entry);
    } finally {
      _pickingSource = false;
    }
  }

  /// Copies [entry] first, then switches the source to it.
  ///
  /// The copy is what makes the source survive deleting the original photo. If
  /// it cannot be made (no space, read or write failure), the previous source
  /// stays untouched and only an error is reported.
  Future<void> _copyAndApply(AvesEntry entry) async {
    setState(() => _copying = true);
    try {
      final artwork = await _controller.copySingleArtwork(entry);
      if (!mounted) return;
      setState(() => _singleEntry = entry);
      await _apply(
        _scope.copyWith(
          kind: WallpaperSourceKind.single,
          singleEntryId: entry.id,
          singleArtwork: artwork,
        ),
      );
    } on WallpaperSingleCopyException catch (error, stack) {
      if (!mounted) return;
      wallpaperLog.w('single artwork copy failed', error, stack);
      unawaited(_showCopyError(error));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _showCopyError(WallpaperSingleCopyException error) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.muzeiWallpaperSourceCopyErrorTitle),
        content: Text(error.isNoSpace ? l10n.muzeiWallpaperSourceCopyNoSpace : l10n.muzeiWallpaperSourceCopyFailed),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(WallpaperSourceScope scope) async {
    if (!scope.isConfigured) return;
    setState(() {
      _scope = scope;
      _applying = true;
    });
    try {
      await _controller.setScope(scope);
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _scope = _controller.prefs.scope;
        });
      }
    }
  }

  String? get _singleTitle => _scope.singleArtwork?.title ?? _singleEntry?.bestTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final working = _applying || _controller.busy;
        return AvesScaffold(
          appBar: AppBar(
            title: Text(l10n.muzeiWallpaperSources),
          ),
          body: Stack(
            children: [
              SafeArea(
                child: ListView(
                  children: [
                    if (working) const LinearProgressIndicator(),
                    RadioGroup<WallpaperSourceKind>(
                      groupValue: _scope.kind,
                      onChanged: (kind) => unawaited(_selectKind(kind)),
                      child: Column(
                        children: [
                          RadioListTile<WallpaperSourceKind>(
                            value: WallpaperSourceKind.myPhotos,
                            title: Text(l10n.muzeiWallpaperSourcesMyPhotos),
                            subtitle: _scope.filters.isEmpty ? Text(l10n.muzeiWallpaperSourcesAllPhotos) : null,
                            secondary: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_scope.kind == WallpaperSourceKind.myPhotos && _scope.filters.isNotEmpty)
                                  IconButton(
                                    tooltip: l10n.muzeiWallpaperSourcesUseAllPhotos,
                                    icon: const Icon(AIcons.filterOff),
                                    onPressed: working ? null : () => unawaited(_confirmClearSource()),
                                  ),
                                IconButton(
                                  tooltip: l10n.muzeiWallpaperSourcesEditPhotos,
                                  icon: const Icon(AIcons.edit),
                                  onPressed: working ? null : _pickSource,
                                ),
                              ],
                            ),
                          ),
                          if (_scope.kind == WallpaperSourceKind.myPhotos && _scope.filters.isNotEmpty)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(bottom: 8),
                              child: FilterBar(
                                filters: _scope.filters,
                                interactive: false,
                                // The chip's own cross is Aves' usual way to drop a
                                // filter; here it returns the source to all photos.
                                onRemove: (_) => unawaited(_clearSource()),
                              ),
                            ),
                          RadioListTile<WallpaperSourceKind>(
                            value: WallpaperSourceKind.single,
                            title: Text(l10n.muzeiWallpaperSourcesSingle),
                            subtitle: Text(_singleTitle ?? l10n.muzeiWallpaperSourcesChooseArtwork),
                            secondary: IconButton(
                              tooltip: l10n.muzeiWallpaperSourcesChooseArtwork,
                              icon: const Icon(AIcons.image),
                              onPressed: working ? null : _pickSingle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(AIcons.image, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.muzeiWallpaperSourcesPhotosOnly,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        _statusText(context, _controller.resolution),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_copying) const Positioned.fill(child: _CopyingOverlay()),
            ],
          ),
          floatingActionButton: WallpaperOverflowFab(
            controller: _controller,
            section: WallpaperSection.sources,
          ),
        );
      },
    );
  }

  String _statusText(BuildContext context, WallpaperSourceResolution? resolution) {
    final l10n = context.l10n;
    return switch (resolution?.status) {
      WallpaperSourceStatus.ready => l10n.muzeiWallpaperSourcesCount(resolution!.total),
      WallpaperSourceStatus.empty => l10n.muzeiWallpaperEmpty,
      WallpaperSourceStatus.unsupported => l10n.muzeiWallpaperUnsupported,
      WallpaperSourceStatus.missing => l10n.muzeiWallpaperMissing,
      null => '',
    };
  }
}

/// Blocks the source page while the copy is written.
///
/// Only the state and the elapsed time are shown: the copy has no meaningful
/// percentage (the bytes arrive in one stream from the platform), and the
/// artwork itself is already chosen. The elapsed time is enough to tell a slow
/// HEIC decode from a frozen page.
class _CopyingOverlay extends StatefulWidget {
  const new();

  @override
  State<_CopyingOverlay> createState() => _CopyingOverlayState();
}

class _CopyingOverlayState extends State<_CopyingOverlay> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final elapsed = _stopwatch.elapsed;
    final time = '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.muzeiWallpaperSourceCopying, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(time, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
