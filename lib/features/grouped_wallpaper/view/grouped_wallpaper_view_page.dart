import 'dart:async';
import 'dart:io';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_history_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_actions.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_cover.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_share_uri.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_artwork_panel.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:material_ui/material_ui.dart';

/// Immersive view of the photo the grouped wallpaper is showing.
///
/// The photo fills the screen and the chrome uses the same bottom panel as
/// Muzei's artwork screen: a title, the line that says what touching does, and
/// the overflow menu. The line names the group and its count here, because a
/// group *is* the source, but its gestures are Muzei's: a tap opens the photo in
/// the viewer, a long press hands it to another app.
class GroupedWallpaperViewPage extends StatefulWidget {
  static const routeName = '/grouped_wallpaper/view';

  /// Whether the playing group's page is already below this view.
  ///
  /// A wallpaper gesture pushes the view over the playing group's page, and the
  /// group page's menu opens the view from itself, so "open wallpaper group"
  /// pops back to that page. Only a view without one has to replace itself.
  final bool groupPageBelow;

  const new({super.key, this.groupPageBelow = false});

  @override
  State<GroupedWallpaperViewPage> createState() => _GroupedWallpaperViewPageState();
}

enum _ViewAction {
  openGroups,
  openInGallery,
  viewWholeGroup,
  toggleGalleryRange,
  share,
  history,
}

class _GroupedWallpaperViewPageState extends State<GroupedWallpaperViewPage> {
  final TransformationController _viewport = TransformationController();

  GroupedWallpaperState? _state;
  AvesEntry? _entry;
  String? _photo;
  bool _loading = true;

  /// Whether a previous/next step is in flight.
  ///
  /// Both controls are inert meanwhile so two steps cannot queue on the engine
  /// and land on a frame the page never shows.
  bool _busy = false;

  /// The chrome is on when the page opens, so the back button and the photo's
  /// context are visible without a first tap; a tap toggles it, like Muzei.
  bool _chromeVisible = true;

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
    // `current` may name another slot than the frame the renderer painted (it
    // promotes on its own, and a reload keeps the slot it had); the entry, the
    // title and the aspect ratio below must all describe the photo on screen.
    final state = await wallpaperEngineLink.readDisplayedState();
    // The view shows the wallpaper's own pixels, effects included; the entry
    // still points at the original photo for "open in gallery" and share.
    final photo = await wallpaperEngineLink.currentEffectPhotoPath();
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

  /// Steps the wallpaper to the previous or next photo and re-reads what it now
  /// shows.
  ///
  /// The step acts on the wallpaper itself, not on a page-local gallery: the
  /// user asked the wallpaper to move, so the frame, the notification and the
  /// queue all follow. The photo, the entry and the menu actions are then read
  /// back, so "open in gallery" and "share" describe the photo on screen.
  Future<void> _step({required bool previous}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (previous) {
        await wallpaperEngineLink.previousArtwork();
      } else {
        await wallpaperEngineLink.nextArtwork();
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      _showMissing();
      return;
    }
    await _pushImmersive(
      MaterialPageRoute(
        settings: const RouteSettings(name: EntryViewerPage.routeName),
        builder: (_) => EntryViewerPage(initialEntry: entry),
      ),
    );
  }

  /// Opens the whole group's media set, not just this photo.
  ///
  /// The range is the group's own, so this is what the wallpaper may draw from;
  /// the gallery's visible range still joins it, because browsing says so
  /// everywhere else too (the media set explains an empty result).
  Future<void> _openWholeGroup() async {
    final groupId = _state?.groupId;
    if (groupId == null || groupId.isEmpty || groupId == wallpaperGroupNoneId) return;
    final range = await wallpaperGroupController.groupRange(groupId);
    if (!mounted) return;
    final mediaSet = wallpaperMediaSetFilter(range);
    _setSystemUiVisible(true);
    await AvesNavItem(route: CollectionPage.routeName, filters: <CollectionFilter>{mediaSet ?? MimeFilter.image}).goTo(context, topLevel: false);
    if (!mounted) return;
    _setSystemUiVisible(false);
  }

  /// Hands the photo to another app through the system chooser.
  ///
  /// A long press is the direct gesture for "I want to do something else with
  /// this photo", like the viewer's own long press, so it bypasses a menu of
  /// our own. The URI and the wildcard type follow the Muzei page: a file URI is
  /// wrapped in the app's FileProvider natively, and a receiver that only claims
  /// a narrower type still appears. A failure must be visible — a silent chooser
  /// reads as a gesture that does nothing.
  Future<void> _openWith() async {
    final entry = _entry;
    if (entry == null) {
      _showMissing();
      return;
    }
    // The chooser is a system surface: it must not appear under hidden bars.
    _setSystemUiVisible(true);
    final opened = await appService.open(wallpaperShareUri(entry), entry.mimeTypeAnySubtype, forceChooser: true);
    if (!mounted) return;
    _setSystemUiVisible(false);
    if (opened) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.noMatchingAppDialogMessage)));
  }

  void _showMissing() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.groupedWallpaperViewMissing)));
  }

  /// Pushes a normal page over this immersive one, then takes the bars away
  /// again.
  ///
  /// This page hides the system bars on entry, so a pushed page would draw its
  /// app bar under the status bar. The bars come back for the pushed page and
  /// are hidden again only when the user returns here.
  Future<void> _pushImmersive(Route<void> route) async {
    _setSystemUiVisible(true);
    await Navigator.of(context).push(route);
    if (!mounted) return;
    _setSystemUiVisible(false);
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
        if (widget.groupPageBelow) {
          // The group page is the "source" of what is on screen and is already
          // below this view, so going back is what the user means.
          navigator.pop();
        } else {
          // Defensive: a view without its group page below replaces itself, so
          // back from the group page never returns to a stale artwork.
          _setSystemUiVisible(true);
          await navigator.pushReplacement(
            MaterialPageRoute(
              settings: const RouteSettings(name: GroupedWallpaperPage.routeName),
              builder: (_) => const GroupedWallpaperPage(),
            ),
          );
        }
      case _ViewAction.openInGallery:
        await _openInGallery();
      case _ViewAction.viewWholeGroup:
        await _openWholeGroup();
      case _ViewAction.toggleGalleryRange:
        // Restoring is always allowed; ignoring a locked range needs its PIN.
        final suspended = VisibleRangeGate.overlay?.gallerySuspended ?? false;
        if (!suspended && visibleRangeController.gallery.locked && !await ensureVisibleRangeUnlocked(context)) return;
        if (!mounted) return;
        VisibleRangeGate.setGallerySuspended(!suspended);
      case _ViewAction.share:
        await _share();
      case _ViewAction.history:
        await _pushImmersive(
          MaterialPageRoute(
            settings: const RouteSettings(name: GroupedWallpaperHistoryPage.routeName),
            builder: (_) => GroupedWallpaperHistoryPage(groupId: _state?.groupId),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _state;
    final entry = _entry;
    final title = state?.entryTitle ?? '';
    final canOpenGroup = state != null && state.groupId.isNotEmpty && state.groupId != wallpaperGroupNoneId;
    final canPrevious = state != null && groupedWallpaperCanGoPrevious(state);
    final canNext = state != null && groupedWallpaperCanGoNext(state);
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
                  // The direct gesture for "do something else with this photo",
                  // like the viewer's own long press: the chooser, no menu.
                  onLongPress: () => unawaited(_openWith()),
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
                    child: const Row(children: [BackButton(color: Colors.white)]),
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
                // The same panel Muzei's artwork screen uses: the two pages are
                // the same "look at the photo" surface, so they must not drift.
                child: WallpaperArtworkPanel(
                  title: title.isEmpty ? null : title,
                  subtitle: state == null ? null : l10n.groupedWallpaperViewInfo(state.groupName, state.count),
                  onViewArtwork: () => unawaited(_openInGallery()),
                  onOpenWith: () => unawaited(_openWith()),
                  actions: [
                    IconButton(
                      tooltip: l10n.wallpaperGroupPreviousPhoto,
                      color: Colors.white,
                      disabledColor: Colors.white38,
                      onPressed: canPrevious && !_busy ? () => unawaited(_step(previous: true)) : null,
                      icon: const Icon(AIcons.previousArtwork),
                    ),
                    IconButton(
                      tooltip: l10n.wallpaperGroupNextPhoto,
                      color: Colors.white,
                      disabledColor: Colors.white38,
                      onPressed: canNext && !_busy ? () => unawaited(_step(previous: false)) : null,
                      icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AIcons.nextArtwork),
                    ),
                    PopupMenuButton<_ViewAction>(
                      icon: const Icon(AIcons.more, color: Colors.white),
                      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                      onSelected: (action) => unawaited(_onAction(action)),
                      itemBuilder: (context) {
                        final suspended = VisibleRangeGate.overlay?.gallerySuspended ?? false;
                        return [
                          PopupMenuItem(
                            value: _ViewAction.openGroups,
                            child: _menuRow(AIcons.wallpaper, l10n.groupedWallpaperViewOpenGroups),
                          ),
                          PopupMenuItem(
                            value: _ViewAction.openInGallery,
                            enabled: entry != null,
                            child: _menuRow(AIcons.image, l10n.groupedWallpaperViewOpenInGallery),
                          ),
                          if (canOpenGroup)
                            PopupMenuItem(
                              value: _ViewAction.viewWholeGroup,
                              child: _menuRow(AIcons.allCollection, l10n.groupedWallpaperViewWholeGroup),
                            ),
                          // The same switch the wallpaper page's overflow menu
                          // and the media set's strip offer: this page is often
                          // where the user notices the range hides the photos.
                          // Restoring is always allowed; ignoring the range is
                          // what the range lock forbids.
                          if (VisibleRangeGate.galleryRestricted)
                            PopupMenuItem(
                              value: _ViewAction.toggleGalleryRange,
                              enabled: suspended || !VisibleRangeGate.galleryLocked,
                              child: _menuRow(
                                suspended ? AIcons.visibleRangeActive : AIcons.visibleRangeInactive,
                                suspended ? l10n.wallpaperGroupRestoreGalleryRange : l10n.wallpaperGroupCancelGalleryRange,
                              ),
                            ),
                          PopupMenuItem(
                            value: _ViewAction.share,
                            enabled: entry != null,
                            child: _menuRow(AIcons.share, l10n.groupedWallpaperViewShare),
                          ),
                          PopupMenuItem(
                            value: _ViewAction.history,
                            child: _menuRow(AIcons.history, l10n.wallpaperGroupHistoryTitle),
                          ),
                        ];
                      },
                    ),
                  ],
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
