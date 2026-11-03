import 'dart:async';
import 'dart:io';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/view/viewer_delete_policy.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_view_group_target.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_empty_notice.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_auto_advance_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_effects_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_gestures_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_history_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_actions.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_cover.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_share_uri.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_artwork_panel.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/multipage.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:aves/widgets/viewer/action/entry_action_delegate.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Immersive view of the photo the grouped wallpaper is showing.
///
/// The photo fills the screen and the chrome uses the same bottom panel as
/// Muzei's artwork screen: a title, the line that says what touching does, and
/// the overflow menu. The line names the group and its count here, because a
/// group *is* the source, but its gestures are Muzei's: a tap opens the photo in
/// the viewer, a long press hands it to another app.
///
/// The page is also the app's own control of the live wallpaper: the bottom panel
/// steps the photos and the groups, and the menu can manage everything the group
/// page's menu can do without a draft (effects, gestures, the lock, deleting the
/// photo on screen, turning the wallpaper off).
class GroupedWallpaperViewPage extends StatefulWidget {
  static const routeName = '/grouped_wallpaper/view';

  /// Whether the playing group's page is already below this view.
  ///
  /// A wallpaper gesture pushes the view over the playing group's page, and the
  /// group page's menu opens the view from itself, so "open wallpaper group" is
  /// a back instead of a replacement.
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
  autoAdvance,
  effects,
  gestures,
  switchSurface,
  toggleNotification,
  disableWallpaper,
  deletePhoto,
  lockGroup,
  unlockGroup,
  about,
}

/// A manual step that is waiting for its frame.
///
/// A step the renderer can promote never waits, so a pending step is always one
/// that had to bake: the title then says what is happening and every step control
/// is inert, exactly like the notification bar.
enum _PendingStep {
  previousPhoto,
  nextPhoto,
  previousGroup,
  nextGroup,
}

class _GroupedWallpaperViewPageState extends State<GroupedWallpaperViewPage> with WidgetsBindingObserver {
  final TransformationController _viewport = TransformationController();

  GroupedWallpaperState? _state;
  AvesEntry? _entry;
  String? _photo;
  bool _loading = true;

  /// The surface this page is describing.
  ///
  /// The split group draws a different photo on the lock screen; the menu
  /// switches which one the page manages. The lock surface has no gesture, so
  /// this in-app page is the only way to step it by hand.
  WallpaperSurface _surface = WallpaperSurface.home;

  /// The step in flight, or null when the page is idle.
  _PendingStep? _pending;

  /// The group a pending switch is heading to, for the title's second line.
  GroupedWallpaperGroup? _pendingGroup;

  /// Aspect ratio of the photo on screen, for the cover layout.
  double? _aspect;

  /// The chrome is on when the page opens, so the back button and the photo's
  /// context are visible without a first tap; a tap toggles it, like Muzei.
  bool _chromeVisible = true;

  /// Geometry the viewport was last centered for.
  (Size, Size)? _geometry;

  bool get _stepping => _pending != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    wallpaperLockService.addListener(_onLockChanged);
    // The page can be the app's first screen (the notification body opens it),
    // and the menu decides from the lock, so make sure it is loaded.
    unawaited(wallpaperLockService.init());
    _setSystemUiVisible(false);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    wallpaperLockService.removeListener(_onLockChanged);
    _setSystemUiVisible(true);
    _viewport.dispose();
    super.dispose();
  }

  /// Rebuilds the controls when the group lock changes elsewhere (the group
  /// page, the bar, or the settings page).
  void _onLockChanged() {
    if (mounted) setState(() {});
  }

  /// Re-reads the frame when the page comes back into the foreground.
  ///
  /// The wallpaper can change while this page is away (a pushed group or viewer
  /// page, or an auto-advance run), so returning must describe what is drawn now
  /// rather than the frame the page opened on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  /// Hides the system bars while looking at the photo, and restores them on any
  /// exit path (route pop, back gesture, or the whole page being disposed).
  static void _setSystemUiVisible(bool visible) {
    unawaited(AvesApp.showSystemUI(visible));
  }

  Future<void> _load() async {
    // One snapshot, because `current` may name another slot than the frame the
    // renderer painted (it promotes on its own, and a reload keeps the slot it
    // had): the entry, the title, the aspect ratio and the pixels below must all
    // describe the photo on screen. The snapshot also carries whether that
    // surface draws the lock effect image.
    final frame = await wallpaperEngineLink.readDisplayedFrame(surface: _surface);
    final state = frame?.state;
    // The decoy is not a queue slot: its single frame carries the metadata.
    final lock = _surface.isLock ? state?.lock : null;
    final slot = _surface.isLock ? null : state?.currentSlot;
    final uri = _surface.isLock ? lock?.uri : slot?.uri;
    AvesEntry? entry;
    if (uri != null && uri.isNotEmpty) {
      final entries = await localMediaDb.loadEntriesByUris({uri});
      entry = entries.firstOrNull;
    }
    final aspect = _surface.isLock ? (lock != null && lock.width > 0 && lock.height > 0 ? lock.width / lock.height : null) : slot?.aspectRatio;
    if (!mounted) return;
    setState(() {
      _state = state;
      _entry = entry;
      _photo = frame?.photoPath;
      _aspect = aspect;
      _loading = false;
    });
  }

  /// Steps the wallpaper to the previous or next photo and re-reads what it now
  /// shows.
  ///
  /// The home queue already holds both neighbours, so the step first asks the
  /// renderer to promote the one it has: that is a texture swap, the same move a
  /// wallpaper double tap makes, and the page can describe the new photo at once.
  /// Only a step it cannot promote (no live engine, the neighbour still baking,
  /// or the lock decoy, which has no queue by design) waits for a bake, and only
  /// then does the page show what it is doing.
  Future<void> _step({required bool previous}) async {
    if (_stepping) return;
    if (!_surface.isLock && await wallpaperEngineLink.promotePhoto(previous: previous)) {
      await _load();
      return;
    }
    if (!mounted) return;
    setState(() {
      _pending = previous ? _PendingStep.previousPhoto : _PendingStep.nextPhoto;
      _pendingGroup = null;
    });
    try {
      if (_surface.isLock) {
        if (previous) {
          await wallpaperEngineLink.previousLockArtwork();
        } else {
          await wallpaperEngineLink.nextLockArtwork();
        }
      } else if (previous) {
        await wallpaperEngineLink.previousArtwork();
      } else {
        await wallpaperEngineLink.nextArtwork();
      }
      await _load();
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  /// Steps to the next or previous enabled group and re-reads the frame.
  ///
  /// A group change selects another range and bakes, so there is no instant path:
  /// like the bar, the page names the target while it waits and greys every step
  /// control. The rotation only walks the enabled groups and never enters group 0,
  /// which is "nothing is playing".
  Future<void> _stepGroup({required bool next}) async {
    if (_stepping) return;
    final state = _state;
    if (state == null) return;
    final delta = next ? 1 : -1;
    final target = groupedWallpaperViewGroupTarget(groups: state.groups, currentId: state.groupId, delta: delta);
    if (target == null) return;
    setState(() {
      _pending = next ? _PendingStep.nextGroup : _PendingStep.previousGroup;
      _pendingGroup = target;
    });
    try {
      await wallpaperEngineLink.switchGroup(delta);
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _pending = null;
          _pendingGroup = null;
        });
      }
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
    final range = await wallpaperGroupController.groupRange(groupId, surface: _surface);
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
  /// a narrower type still appears. A failure must be visible �?a silent chooser
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
        } else if (groupedWallpaperNavController.mode == GroupedWallpaperNavMode.shared) {
          // The shared entry hosts both pages: switch it and push the shell so
          // the bar highlights the entry the user lands on.
          _setSystemUiVisible(true);
          visibleRangeDestination.value = VisibleRangeDestination.wallpaper;
          await navigator.pushReplacement(
            MaterialPageRoute(
              settings: const RouteSettings(name: VisibleRangePage.routeName),
              builder: (_) => const VisibleRangeShellPage(selectCurrentWallpaperGroup: true),
            ),
          );
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
      case _ViewAction.autoAdvance:
        await _openAutoAdvance();
      case _ViewAction.effects:
        await _openEffects();
      case _ViewAction.gestures:
        await _openGestures();
      case _ViewAction.toggleNotification:
        await _toggleNotification();
      case _ViewAction.switchSurface:
        await _switchSurface();
      case _ViewAction.disableWallpaper:
        await _disableWallpaper();
      case _ViewAction.deletePhoto:
        _deletePhoto();
      case _ViewAction.lockGroup:
        await _lockGroup();
      case _ViewAction.unlockGroup:
        await _unlockGroup();
      case _ViewAction.about:
        await _openAbout();
    }
  }

  /// Switches the page between the home photo and the lock decoy.
  ///
  /// The menu entry only acts for a split group; the lock surface has no gesture,
  /// so this page is where the user manages its previous/next by hand. It also
  /// offers the switch before the decoy has been baked: the first "next" then
  /// bakes one instead of the control being unreachable.
  Future<void> _switchSurface() async {
    if (!_hasLockSurface) return;
    setState(() {
      _surface = _surface.isLock ? WallpaperSurface.home : WallpaperSurface.lock;
      _loading = true;
    });
    await _load();
  }

  /// Whether the viewed group keeps a separate lock range.
  ///
  /// `lockRangeId` is written with the split, so this is true before the decoy
  /// has a photo: the menu can then offer the switch and the first step bakes it.
  bool get _hasLockSurface {
    final state = _state;
    return state != null && (state.lock != null || state.lockRangeId.isNotEmpty);
  }

  /// Opens the playing group's auto-advance editor.
  ///
  /// The interval belongs to the group, not to the surface, so this is the same
  /// page the effects editor and the wallpaper page open.
  Future<void> _openAutoAdvance() async {
    final groupId = _state?.groupId ?? '';
    if (groupId.isEmpty || groupId == wallpaperGroupNoneId) return;
    // A gesture can cold-start the app, so the group list may not be loaded yet.
    await wallpaperGroupController.init();
    if (!mounted) return;
    await _pushImmersive(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperAutoAdvancePage.routeName),
        builder: (_) => GroupedWallpaperAutoAdvancePage(groupId: groupId, controller: wallpaperGroupController),
      ),
    );
  }

  /// Opens the effects editor for the playing group.
  ///
  /// The editor only needs the group aggregate, not the wallpaper page's range
  /// draft: effects are written straight through, so the view can manage them
  /// without saving the page.
  Future<void> _openEffects() async {
    final groupId = _state?.groupId ?? '';
    if (groupId.isEmpty || groupId == wallpaperGroupNoneId) return;
    await wallpaperGroupController.init();
    if (!mounted) return;
    await _pushImmersive(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperEffectsPage.routeName),
        builder: (_) => GroupedWallpaperEffectsPage(groupId: groupId, controller: wallpaperGroupController),
      ),
    );
    await _load();
  }

  /// Opens the global gesture bindings.
  Future<void> _openGestures() async {
    await _pushImmersive(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperGesturesPage.routeName),
        builder: (_) => const GroupedWallpaperGesturesPage(),
      ),
    );
    await _load();
  }

  /// Opens the wallpaper's explanation, which also documents the lock and the
  /// notification's button sets.
  Future<void> _openAbout() async {
    await _pushImmersive(
      MaterialPageRoute(
        settings: const RouteSettings(name: VisibleRangeAboutPage.routeName),
        builder: (_) => const VisibleRangeAboutPage(wallpaperFirst: true),
      ),
    );
  }

  Future<void> _toggleNotification() async {
    final enabled = _state?.notification ?? true;
    await wallpaperEngineLink.setNotification(!enabled);
    await _load();
    if (!mounted || enabled) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperNotificationOffHint)));
  }

  /// Turns the grouped wallpaper off without touching what is on screen.
  ///
  /// The same action as the group page's: the last frame stays, and the wallpaper
  /// simply stops following its group. The page keeps describing that frame.
  Future<void> _disableWallpaper() async {
    if (_stepping) return;
    await wallpaperEngineLink.setDisabled(true);
    await wallpaperEngineLink.prepare();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperGroupWallpaperDisabled)));
  }

  /// Whether the photo on screen can be deleted from here.
  ///
  /// The viewer's own visibility rule is the source of truth: read-only and
  /// browse-only modes and a photo that cannot be edited are refused, and a stack
  /// (RAW + JPEG) is left to the gallery viewer, which hosts the multi-page
  /// conductor its delete needs.
  bool get _canDeletePhoto {
    final entry = _entry;
    if (entry == null || _stepping || entry.isStack) return false;
    final appMode = context.read<ValueNotifier<AppMode>>().value;
    return EntryActionDelegate(entry, entry, null).isVisible(appMode: appMode, action: EntryAction.delete);
  }

  /// Deletes the photo on screen, then shows the next one.
  ///
  /// The deletion itself is the viewer's action, so the recycling bin, the
  /// confirmations, the progress report and the source refresh behave exactly as
  /// in the gallery; the policy below only reports success, which is when the
  /// wallpaper steps. Deleting is the one action that must not keep showing the
  /// photo, which is why the step is unconditional on success.
  void _deletePhoto() {
    final entry = _entry;
    if (entry == null || !_canDeletePhoto) return;
    final deletedEntryId = entry.id;
    EntryActionDelegate(
      entry,
      entry,
      null,
      viewerDeletePolicy: _DeleteThenAdvancePolicy(onDeleted: () => unawaited(_advanceAfterDelete(deletedEntryId: deletedEntryId))),
    ).onActionSelected(context, EntryAction.delete);
  }

  /// Shows the next photo after a delete, on the surface being viewed.
  Future<void> _advanceAfterDelete({required int deletedEntryId}) async {
    await _step(previous: false);
    if (!mounted) return;
    // With nothing left to show, the engine keeps the frame already on screen
    // (the empty-group rule), which is the photo the user just deleted. The page
    // explains why nothing moved instead of looking like it ignored the action.
    final state = _state;
    final stillShowing = _surface.isLock ? state?.lock?.entryId == deletedEntryId : state?.currentSlot?.entryId == deletedEntryId;
    if (stillShowing) _explainEmptyGroup();
  }

  /// Explains that the deleted photo was the group's last one.
  ///
  /// The notice is consumed here so the group page below does not ask again; it
  /// dedupes per episode, and a successful bake starts a new one.
  void _explainEmptyGroup() {
    final l10n = context.l10n;
    final name = groupedWallpaperEmptyNotice.groupName ?? _state?.groupName ?? '';
    groupedWallpaperEmptyNotice.dismiss();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.wallpaperGroupEmptyTitle),
          content: Text(l10n.wallpaperGroupEmptyMessage(name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
          ],
        ),
      ),
    );
  }

  /// Locks the group on screen, exactly like the bar's lock button.
  ///
  /// Locking adds protection, so it asks for nothing; unlocking is the action
  /// that needs the PIN.
  Future<void> _lockGroup() async {
    final groupId = _state?.groupId ?? '';
    if (groupId.isEmpty || groupId == wallpaperGroupNoneId) return;
    await wallpaperLockService.init();
    await wallpaperLockService.lockGroup(groupId);
    await wallpaperEngineLink.refreshLock();
    await _load();
  }

  Future<void> _unlockGroup() async {
    if (await promptGroupSwitchUnlock(context)) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _state;
    final entry = _entry;
    final locked = wallpaperLockService.groupSwitchLocked;
    final lock = _surface.isLock ? state?.lock : null;
    final photoTitle = _surface.isLock ? (lock?.title ?? '') : (state?.entryTitle ?? '');
    final title = switch (_pending) {
      _PendingStep.previousPhoto => l10n.wallpaperGroupSwitchingPrevious,
      _PendingStep.nextPhoto => l10n.wallpaperGroupSwitchingNext,
      _PendingStep.previousGroup || _PendingStep.nextGroup => l10n.wallpaperGroupSwitching,
      null => photoTitle,
    };
    final pendingGroup = _pendingGroup;
    final status = state != null && pendingGroup != null
        ? l10n.wallpaperGroupSwitchingInfo(state.groupNumber, state.groupName, pendingGroup.number, pendingGroup.name)
        : null;
    final canOpenGroup = state != null && state.groupId.isNotEmpty && state.groupId != wallpaperGroupNoneId;
    final hasLockSurface = _hasLockSurface;
    final disabled = state?.status == GroupedWallpaperStatus.disabled;
    final canPrevious = _surface.isLock ? (lock?.recent.any((record) => record.entryId != lock.entryId) ?? false) : state != null && groupedWallpaperCanGoPrevious(state);
    // The lock surface can be stepped before it has a frame: the first step is
    // what bakes the decoy, so gating on `lock != null` would make it unreachable.
    final canNext = _surface.isLock ? hasLockSurface : state != null && groupedWallpaperCanGoNext(state);
    final canStepGroup = state != null && groupedWallpaperCanStepGroup(state, locked: locked);
    // Locking is the bar's rule: an unlocked lock needs a real group on screen,
    // and the button only offers a lock the guard would actually enforce.
    final canLock = !locked && canOpenGroup && state.status == GroupedWallpaperStatus.ready;
    final canDelete = _canDeletePhoto;
    final subtitle = state == null
        ? null
        : _surface.isLock
        ? state.groupName
        : l10n.groupedWallpaperViewInfo(state.groupName, state.count);
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
                  _surface.isLock && hasLockSurface ? l10n.wallpaperGroupLockNotBaked : l10n.groupedWallpaperViewEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final viewportSize = constraints.biggest;
                final childSize = coverSizeFor(viewportSize, _aspect);
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
                  status: status,
                  subtitle: subtitle,
                  onViewArtwork: () => unawaited(_openInGallery()),
                  onOpenWith: () => unawaited(_openWith()),
                  actions: [
                    // The group steps sit above the photo steps: they act on the
                    // rotation, which is the coarser move, and keeping them on
                    // their own row leaves both pairs at a comfortable size.
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.wallpaperGroupPreviousGroup,
                              color: Colors.white,
                              disabledColor: Colors.white38,
                              onPressed: canStepGroup && !_stepping ? () => unawaited(_stepGroup(next: false)) : null,
                              icon: _pending == _PendingStep.previousGroup ? _spinner : const Icon(AIcons.down),
                            ),
                            IconButton(
                              tooltip: l10n.wallpaperGroupNextGroup,
                              color: Colors.white,
                              disabledColor: Colors.white38,
                              onPressed: canStepGroup && !_stepping ? () => unawaited(_stepGroup(next: true)) : null,
                              icon: _pending == _PendingStep.nextGroup ? _spinner : const Icon(AIcons.up),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _surface.isLock ? l10n.wallpaperGroupLockPrevious : l10n.wallpaperGroupPreviousPhoto,
                              color: Colors.white,
                              disabledColor: Colors.white38,
                              onPressed: canPrevious && !_stepping ? () => unawaited(_step(previous: true)) : null,
                              icon: _pending == _PendingStep.previousPhoto ? _spinner : const Icon(AIcons.previousArtwork),
                            ),
                            IconButton(
                              tooltip: _surface.isLock ? l10n.wallpaperGroupLockNext : l10n.wallpaperGroupNextPhoto,
                              color: Colors.white,
                              disabledColor: Colors.white38,
                              onPressed: canNext && !_stepping ? () => unawaited(_step(previous: false)) : null,
                              icon: _pending == _PendingStep.nextPhoto ? _spinner : const Icon(AIcons.nextArtwork),
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
                                  if (canOpenGroup)
                                    PopupMenuItem(
                                      value: _ViewAction.autoAdvance,
                                      child: _menuRow(AIcons.autoAdvance, l10n.muzeiWallpaperAutoAdvance),
                                    ),
                                  if (canOpenGroup)
                                    PopupMenuItem(
                                      value: _ViewAction.effects,
                                      child: _menuRow(AIcons.palette, l10n.muzeiWallpaperEffects),
                                    ),
                                  PopupMenuItem(
                                    value: _ViewAction.gestures,
                                    child: _menuRow(AIcons.gestures, l10n.wallpaperGroupGestures),
                                  ),
                                  const PopupMenuDivider(),
                                  // The decoy is managed here, not on the lock screen:
                                  // its gestures are deliberately inert. The entry stays
                                  // visible for a group without a split so the menu says
                                  // why there is nothing to switch to, instead of hiding
                                  // the control the user is looking for.
                                  PopupMenuItem(
                                    value: _ViewAction.switchSurface,
                                    enabled: hasLockSurface,
                                    child: _menuRow(
                                      AIcons.visibleRangeActive,
                                      !hasLockSurface
                                          ? l10n.wallpaperGroupNoLockSurface
                                          : _surface.isLock
                                          ? l10n.wallpaperGroupViewHomeWallpaper
                                          : l10n.wallpaperGroupViewLockWallpaper,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: _ViewAction.toggleNotification,
                                    child: _menuRow(
                                      (state?.notification ?? true) ? AIcons.checked : AIcons.unselected,
                                      l10n.wallpaperGroupNotification,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: _ViewAction.disableWallpaper,
                                    enabled: !disabled && wallpaperEngineLink.isAttached,
                                    child: _menuRow(AIcons.wallpaperStopped, l10n.wallpaperGroupDisableWallpaper),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: _ViewAction.deletePhoto,
                                    enabled: canDelete,
                                    child: _menuRow(AIcons.delete, l10n.groupedWallpaperViewDelete),
                                  ),
                                  // The group lock is the same state as the group
                                  // page's and the bar's: locking never asks, and
                                  // unlocking asks for the group password.
                                  if (locked)
                                    PopupMenuItem(
                                      value: _ViewAction.unlockGroup,
                                      child: _menuRow(AIcons.unlocked, l10n.wallpaperGroupUnlockCurrent),
                                    )
                                  else
                                    PopupMenuItem(
                                      value: _ViewAction.lockGroup,
                                      enabled: canLock && !_stepping,
                                      child: _menuRow(AIcons.locked, l10n.wallpaperGroupLockCurrent),
                                    ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: _ViewAction.about,
                                    child: _menuRow(AIcons.info, l10n.aboutWallpaperTitle),
                                  ),
                                ];
                              },
                            ),
                          ],
                        ),
                      ],
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

  static const _spinner = SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _menuRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Text(text),
    ],
  );
}

/// Tells the page when the viewer's delete actually completed.
///
/// Everything else stays the viewer's own behaviour: the recycling bin, the
/// confirmations, the progress report and the source refresh. Only a successful
/// delete reports back, so a cancelled confirmation or a failed move leaves the
/// wallpaper on the photo it was showing.
class _DeleteThenAdvancePolicy implements ViewerDeletePolicy {
  final VoidCallback _advance;

  new({required VoidCallback onDeleted}) : _advance = onDeleted;

  @override
  bool get replacesStandardConfirmation => false;

  @override
  bool isPrivateCopy(AvesEntry entry) => false;

  @override
  Future<bool> confirmDelete(BuildContext context, AvesEntry entry) async => true;

  @override
  Future<bool> deletePrivateCopy(BuildContext context, AvesEntry entry) async => false;

  @override
  void onDeleted(AvesEntry entry) => _advance();
}
