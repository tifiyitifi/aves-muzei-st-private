import 'dart:async';
import 'dart:io';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_cover.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:material_ui/material_ui.dart';

/// Immersive view of the photo the grouped wallpaper is showing.
///
/// Modelled on Muzei's artwork screen: a full-screen image with pan and zoom and
/// chrome that appears on tap. Its menu opens the wallpaper group page instead of
/// Muzei's "source" entry, because a group *is* the source here, and the bottom
/// bar names the group, its size and the photo, which is what the wallpaper's
/// notification will show too.
class GroupedWallpaperViewPage extends StatefulWidget {
  static const routeName = '/grouped_wallpaper/view';

  /// Whether the group page pushed this view.
  ///
  /// Opening the group page from the view then pops back to it instead of
  /// pushing a second one; a view opened by a wallpaper gesture (cold start)
  /// replaces itself, so back returns to the app's home.
  final bool openedFromGroups;

  const new({super.key, this.openedFromGroups = false});

  @override
  State<GroupedWallpaperViewPage> createState() => _GroupedWallpaperViewPageState();
}

enum _ViewAction {
  openGroups,
  openInGallery,
  share,
}

class _GroupedWallpaperViewPageState extends State<GroupedWallpaperViewPage> {
  final TransformationController _viewport = TransformationController();

  GroupedWallpaperState? _state;
  AvesEntry? _entry;
  String? _photo;
  bool _loading = true;
  bool _chromeVisible = false;

  /// Geometry the viewport was last centered for.
  (Size, Size)? _geometry;

  @override
  void initState() {
    super.initState();
    _setSystemUiVisible(false);
    unawaited(_load());
  }

  @override
  void dispose() {
    _setSystemUiVisible(true);
    _viewport.dispose();
    super.dispose();
  }

  /// Hides the system bars while looking at the photo, and restores them on any
  /// exit path (route pop, back gesture, or the whole page being disposed).
  static void _setSystemUiVisible(bool visible) {
    unawaited(AvesApp.showSystemUI(visible));
  }

  Future<void> _load() async {
    final state = await wallpaperEngineLink.readState();
    final photo = await wallpaperEngineLink.currentPhotoPath();
    final uri = state?.currentSlot?.uri;
    AvesEntry? entry;
    if (uri != null && uri.isNotEmpty) {
      final entries = await localMediaDb.loadEntriesByUris({uri});
      entry = entries.firstOrNull;
    }
    if (!mounted) return;
    setState(() {
      _state = state;
      _entry = entry;
      _photo = photo;
      _loading = false;
    });
  }

  void _syncViewport(Size childSize, Size viewportSize) {
    final geometry = (childSize, viewportSize);
    if (_geometry == geometry) return;
    _geometry = geometry;
    final matrix = centeredCoverMatrix(childSize, viewportSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewport.value = matrix;
    });
  }

  /// Opens the entry in the real viewer, where the user can share, inspect and
  /// zoom it with the gallery's own chrome.
  Future<void> _openInGallery() async {
    final entry = _entry;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.groupedWallpaperViewMissing)));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: EntryViewerPage.routeName),
        builder: (_) => EntryViewerPage(initialEntry: entry),
      ),
    );
  }

  /// Shares the photo through the app's existing share channel.
  Future<void> _share() async {
    final entry = _entry;
    if (entry == null) return;
    final shared = await appService.shareSingle(entry.uri, entry.mimeType);
    if (!mounted || shared) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.genericFailureFeedback)));
  }

  Future<void> _onAction(_ViewAction action) async {
    switch (action) {
      case _ViewAction.openGroups:
        final navigator = Navigator.of(context);
        if (widget.openedFromGroups) {
          // The group page is the "source" of what is on screen and is already
          // below this view, so going back is what the user means.
          navigator.pop();
        } else {
          // A wallpaper gesture cold-started the view on top of the app's home:
          // replace it, so back from the group page returns home instead of
          // showing a stale artwork.
          await navigator.pushReplacement(
            MaterialPageRoute(
              settings: const RouteSettings(name: GroupedWallpaperPage.routeName),
              builder: (_) => const GroupedWallpaperPage(),
            ),
          );
        }
      case _ViewAction.openInGallery:
        await _openInGallery();
      case _ViewAction.share:
        await _share();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _state;
    final entry = _entry;
    final info = state == null ? '' : l10n.groupedWallpaperViewInfo(state.groupName, state.count);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_photo == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.groupedWallpaperViewEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final viewportSize = constraints.biggest;
                final childSize = coverSizeFor(viewportSize, state?.currentSlot?.aspectRatio);
                _syncViewport(childSize, viewportSize);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                  child: InteractiveViewer(
                    transformationController: _viewport,
                    minScale: 1,
                    maxScale: 4,
                    constrained: false,
                    child: SizedBox(
                      width: childSize.width,
                      height: childSize.height,
                      child: Image.file(
                        File(_photo!),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                );
              },
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: .6), Colors.transparent],
                    ),
                  ),
                  child: Padding(
                    // The system bars are hidden here, so `SafeArea` would be
                    // zero; `viewPadding` keeps the chrome clear of a cutout.
                    padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
                    child: Row(
                      children: [
                        const BackButton(color: Colors.white),
                        const Spacer(),
                        PopupMenuButton<_ViewAction>(
                          icon: const Icon(AIcons.more, color: Colors.white),
                          tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                          onSelected: (action) => unawaited(_onAction(action)),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _ViewAction.openGroups,
                              child: _menuRow(AIcons.wallpaper, l10n.groupedWallpaperViewOpenGroups),
                            ),
                            PopupMenuItem(
                              value: _ViewAction.openInGallery,
                              enabled: entry != null,
                              child: _menuRow(AIcons.image, l10n.groupedWallpaperViewOpenInGallery),
                            ),
                            PopupMenuItem(
                              value: _ViewAction.share,
                              enabled: entry != null,
                              child: _menuRow(AIcons.share, l10n.groupedWallpaperViewShare),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: .6), Colors.transparent],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      24,
                      16,
                      16 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          info,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white70,
                            shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                          ),
                        ),
                        if (state != null && state.entryTitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              state.entryTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(text),
        ],
      );
}
